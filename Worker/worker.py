"""OpenPixel's local JSON-lines worker. Stdout is reserved for protocol events."""

from __future__ import annotations

import argparse
import contextlib
import datetime
import gc
import hashlib
import importlib.metadata
import json
import logging
import math
import os
import pathlib
import secrets
import shutil
import sys
import time
import uuid
from typing import Any


CATALOG_PATH = pathlib.Path(__file__).with_name("catalog.json")
MAX_REQUEST_BYTES = 65_536
MAX_REFERENCE_IMAGES = 3
DIMENSIONS = {(768, 768), (1024, 768), (768, 1024)}
HISTORY_STRINGS = (
    "id",
    "modelID",
    "modelName",
    "modelRepo",
    "modelRevision",
    "runtimeVersion",
    "prompt",
    "createdAt",
)


def read_catalog() -> list[dict[str, Any]]:
    """Loads the shipped, revision-pinned model catalog."""
    return json.loads(CATALOG_PATH.read_text(encoding="utf-8"))


def atomic_json(path: pathlib.Path, data: Any) -> None:
    """Commits a JSON file without leaving a partial record on interruption."""
    temporary = path.with_suffix(".tmp")
    temporary.write_text(json.dumps(data, indent=2), encoding="utf-8")
    temporary.replace(path)


def validate_generation(request: dict[str, Any]) -> dict[str, Any]:
    """Rejects unsupported parameters before loading the model into memory."""
    prompt = request.get("prompt")
    if not isinstance(prompt, str) or not prompt.strip():
        raise ValueError("Describe the image you want to create.")
    if len(prompt) > 4000:
        raise ValueError("Keep your prompt under 4,000 characters.")
    width, height = request.get("width", 768), request.get("height", 768)
    if type(width) is not int or type(height) is not int:
        raise ValueError("Image dimensions must be whole numbers.")
    if (width, height) not in DIMENSIONS:
        raise ValueError("Choose Square, Landscape, or Portrait.")
    steps = request.get("steps", 4)
    if type(steps) is not int or not 1 <= steps <= 8:
        raise ValueError("Steps must be between 1 and 8.")
    seed = request.get("seed")
    if seed is None:
        seed = secrets.randbelow(2**32)
    if type(seed) is not int or not 0 <= seed < 2**32:
        raise ValueError("Seed must be between 0 and 4,294,967,295.")
    return dict(
        prompt=prompt.strip(),
        width=width,
        height=height,
        num_inference_steps=steps,
        seed=seed,
    )


def validate_references(
    request: dict[str, Any], inputs: pathlib.Path
) -> list[str]:
    """Accepts reference images only from the app's own inputs directory."""
    images = request.get("images", [])
    if not isinstance(images, list) or not all(
        isinstance(item, str) for item in images
    ):
        raise ValueError("Reference images must be a list of file paths.")
    if len(images) > MAX_REFERENCE_IMAGES:
        raise ValueError(
            f"Use up to {MAX_REFERENCE_IMAGES} reference images at a time."
        )
    root = inputs.resolve()
    paths = []
    for item in images:
        path = pathlib.Path(item).resolve()
        if path.parent != root or not path.is_file():
            raise ValueError(
                "A reference image is missing. Attach it again and retry."
            )
        paths.append(str(path))
    return paths


class CachedPromptEncoding:
    """Caches four evaluated prompt pairs per loaded FLUX.2 weight set.

    Both pinned mflux 0.20.0 Klein variants use the same encoding settings.
    This mixin leaves denoising and decoding to their original implementations.
    """

    def _encode_prompt_pair(
        self, *, prompt: str, negative_prompt: str | None, guidance: float
    ) -> Any:
        import mlx.core as mx

        key = (prompt, negative_prompt, guidance)
        self.prompt_cache_hit = key in self.prompt_cache
        if self.prompt_cache_hit:
            encoded = self.prompt_cache.pop(key)
        else:
            encoded = super()._encode_prompt_pair(
                prompt=prompt,
                negative_prompt=negative_prompt,
                guidance=guidance,
            )
            # Retain values, not lazy graphs that recompute the text encoder.
            mx.eval(*(value for value in encoded if value is not None))
            if len(self.prompt_cache) >= 4:
                del self.prompt_cache[next(iter(self.prompt_cache))]
        self.prompt_cache[key] = encoded
        return encoded


def load_model(
    entry: dict[str, Any],
    path: pathlib.Path,
    edit: bool = False,
    shared: Any = None,
) -> Any:
    """Builds the mflux pipeline named by a catalog entry's architecture."""
    from mflux.models.common.config import ModelConfig

    architecture = entry.get("architecture", "flux2_klein_4b")
    if edit and not entry.get("supportsEditing"):
        raise ValueError(
            f"{entry['name']} can't edit images. Choose FLUX.2 Klein."
        )
    if architecture.startswith("flux2_klein_") and edit:
        from mflux.models.flux2.variants import Flux2KleinEdit as pipeline
    elif architecture.startswith("flux2_klein_"):
        from mflux.models.flux2.variants import Flux2Klein as pipeline
    elif architecture == "z_image_turbo":
        from mflux.models.z_image.variants import ZImageTurbo as pipeline
    else:
        raise ValueError("This version of OpenPixel can't run that model.")
    if architecture.startswith("flux2_klein_"):

        class CachedKlein(CachedPromptEncoding, pipeline):
            """Adds a bounded prompt cache to the selected Klein variant."""

        if shared is not None:
            from mlx import nn

            # Construct only the lightweight variant shell. These are all the
            # attributes set by the pinned Flux2Initializer; arrays are shared,
            # never copied or loaded a second time.
            model = CachedKlein.__new__(CachedKlein)
            nn.Module.__init__(model)
            for name in (
                "model_config",
                "callbacks",
                "tiling_config",
                "tokenizers",
                "vae",
                "transformer",
                "text_encoder",
                "bits",
                "lora_paths",
                "lora_scales",
                "prompt_cache",
            ):
                setattr(model, name, getattr(shared, name))
            return model
        pipeline = CachedKlein
    return pipeline(
        model_config=getattr(ModelConfig, architecture)(), model_path=str(path)
    )


class Worker:
    """Owns app storage and at most one loaded model for sequential requests."""

    def __init__(self, root: pathlib.Path, output: Any = None) -> None:
        self.root = root.resolve()
        self.output = output if output is not None else sys.stdout
        self.catalog = read_catalog()
        self.model = None
        self.loaded_model_id: str | None = None
        self.pipelines: dict[bool, Any] = {}
        self.timings: dict[str, float] = {}
        self.stage_started = 0.0
        self.request_id = ""
        for name in ("Models", "Images", "Logs", "Cache/Inputs"):
            (self.root / name).mkdir(parents=True, exist_ok=True)

    def emit(self, event: str, **values: Any) -> None:
        """Writes one flushed event, including its originating request ID."""
        payload = dict(event=event, requestID=self.request_id, **values)
        self.output.write(json.dumps(payload) + "\n")
        self.output.flush()

    def model_entry(self, model_id: str) -> dict[str, Any]:
        for entry in self.catalog:
            if entry["id"] == model_id:
                return entry
        raise ValueError("This model is not in OpenPixel's supported catalog.")

    def model_path(self, entry: dict[str, Any]) -> pathlib.Path:
        return self.root / "Models" / entry["id"]

    def installed(self, entry: dict[str, Any]) -> bool:
        directory = self.model_path(entry)
        try:
            marker = json.loads((directory / "installed.json").read_text())
            return marker["revision"] == entry["revision"] and all(
                (directory / item["path"]).stat().st_size == item["size"]
                for item in entry["files"]
            )
        except (OSError, ValueError, KeyError):
            return False

    def history(self) -> list[dict[str, Any]]:
        records = []
        for path in (self.root / "Images").glob("*.json"):
            try:
                record = json.loads(path.read_text(encoding="utf-8"))
                image = self.root / "Images" / f"{path.stem}.png"
                valid = isinstance(record, dict) and all(
                    isinstance(record.get(key), str) for key in HISTORY_STRINGS
                )
                valid = valid and all(
                    type(record.get(key)) is int
                    for key in ("seed", "width", "height", "steps")
                )
                valid = valid and 0 <= record["seed"] < 2**32
                valid = (
                    valid
                    and type(record.get("durationSeconds")) in (int, float)
                    and math.isfinite(record["durationSeconds"])
                )
                if valid and image.is_file() and record["id"] == path.stem:
                    record["imagePath"] = str(image)
                    records.append(record)
            except (OSError, ValueError, KeyError, TypeError):
                logging.warning("Ignoring unreadable history: %s", path.name)
        return sorted(records, key=lambda item: item["createdAt"], reverse=True)

    def status(self) -> None:
        self.emit(
            "status",
            models=[
                dict(
                    id=entry["id"],
                    installed=self.installed(entry),
                    partial=self.model_path(entry).exists(),
                )
                for entry in self.catalog
            ],
            history=self.history(),
        )

    def download(self, entry: dict[str, Any]) -> None:
        directory = self.model_path(entry)
        directory.mkdir(parents=True, exist_ok=True)
        remaining = 0
        for item in entry["files"]:
            local = directory / item["path"]
            partial = self.partial_path(local, entry["revision"])
            existing = local if local.exists() else partial
            existing_size = existing.stat().st_size if existing.exists() else 0
            remaining += max(item["size"] - existing_size, 0)
        if shutil.disk_usage(directory).free < remaining + 1024**3:
            raise ValueError(
                "Free up disk space before downloading this model. "
                "OpenPixel also needs 1 GB of working space."
            )

        completed = 0
        for item in entry["files"]:
            self.download_file(entry, item, completed)
            completed += item["size"]
            self.download_progress(completed, entry["sizeBytes"])
        atomic_json(
            directory / "installed.json", dict(revision=entry["revision"])
        )
        self.status()
        self.emit("done", message="Model downloaded. Ready to create.")

    @staticmethod
    def partial_path(local: pathlib.Path, revision: str) -> pathlib.Path:
        return local.with_name(f"{local.name}.{revision}.part")

    def download_progress(self, completed: int, total: int) -> None:
        self.emit(
            "progress",
            stage="downloading",
            message="Downloading model weights…",
            progress=min(completed / total, 1),
            completedBytes=completed,
            totalBytes=total,
        )

    def download_file(
        self, entry: dict[str, Any], item: dict[str, Any], completed: int
    ) -> None:
        """Resumes a pinned file, then verifies it before making it available."""
        # Keep startup independent of network and inference dependencies.
        import requests
        from huggingface_hub import hf_hub_url

        local = self.model_path(entry) / item["path"]
        local.parent.mkdir(parents=True, exist_ok=True)
        partial = self.partial_path(local, entry["revision"])
        if local.exists():
            self.verify_file(local, item)
            return
        offset = partial.stat().st_size if partial.exists() else 0
        if offset > item["size"]:
            partial.unlink()
            offset = 0
        self.download_progress(completed + offset, entry["sizeBytes"])
        if offset < item["size"]:
            headers = {
                "User-Agent": "OpenPixel/0.1.0",
                "Accept-Encoding": "identity",
            }
            if offset:
                headers["Range"] = f"bytes={offset}-"
            url = hf_hub_url(
                entry["repo"], item["path"], revision=entry["revision"]
            )
            with requests.get(
                url, headers=headers, stream=True, timeout=(15, 60)
            ) as response:
                response.raise_for_status()
                if response.status_code == 206:
                    expected = f"bytes {offset}-"
                    content_range = response.headers.get("Content-Range", "")
                    if not content_range.startswith(expected):
                        raise ValueError(
                            "The server returned an invalid download "
                            "range. Try Resume Download again."
                        )
                elif response.status_code == 200:
                    # Some delivery endpoints ignore Range. Never append a full
                    # response to a partial file; safely restart that file.
                    offset = 0
                else:
                    raise ValueError("Unexpected download response. Try again.")
                last_update = 0.0
                with partial.open("ab" if offset else "wb") as destination:
                    for chunk in response.iter_content(chunk_size=1024**2):
                        if not chunk:
                            continue
                        if offset + len(chunk) > item["size"]:
                            raise ValueError(
                                "The model download exceeded its "
                                "expected size. Try again."
                            )
                        destination.write(chunk)
                        offset += len(chunk)
                        now = time.monotonic()
                        if now - last_update > 0.2:
                            self.download_progress(
                                completed + offset, entry["sizeBytes"]
                            )
                            last_update = now
            if offset != item["size"]:
                # Keep partial bytes for a later retry, including truncated
                # responses that a server ended without a transport error.
                raise ValueError(
                    "Download interrupted. Choose Resume Download "
                    "to continue where it stopped."
                )
        self.emit(
            "progress",
            stage="verifying",
            message=f"Checking {item['path']}…",
            progress=(completed + offset) / entry["sizeBytes"],
        )
        self.verify_file(partial, item)
        partial.replace(local)

    @staticmethod
    def verify_file(path: pathlib.Path, item: dict[str, Any]) -> None:
        if path.stat().st_size != item["size"]:
            path.unlink(missing_ok=True)
            raise ValueError(
                "The download was incomplete. Download again to resume."
            )
        if item.get("sha256"):
            with path.open("rb") as source:
                digest = hashlib.file_digest(source, "sha256").hexdigest()
            if digest != item["sha256"]:
                path.unlink(missing_ok=True)
                raise ValueError(
                    "A model file failed its integrity check. "
                    "Download again to repair it."
                )

    def unload(self) -> None:
        self.model = None
        self.pipelines.clear()
        self.loaded_model_id = None
        gc.collect()
        if "mlx.core" in sys.modules:
            import mlx.core as mx

            mx.clear_cache()

    def generate(self, entry: dict[str, Any], request: dict[str, Any]) -> None:
        request_started = time.monotonic()
        parameters = validate_generation(request)
        references = validate_references(
            request, self.root / "Cache" / "Inputs"
        )
        if references and not entry.get("supportsEditing"):
            raise ValueError(
                f"{entry['name']} can't edit images. Choose FLUX.2 Klein."
            )
        if not self.installed(entry):
            raise ValueError("Download the model before generating an image.")
        if shutil.disk_usage(self.root).free < 100 * 1024**2:
            raise ValueError(
                "Free up at least 100 MB to save generated images."
            )
        self.emit(
            "progress", stage="loading", message="Loading model into memory…"
        )
        import mlx.core as mx
        from PIL import PngImagePlugin

        self.timings = {"setup": time.monotonic() - request_started}
        mx.set_cache_limit(256 * 1024**2)
        # Leave space for macOS and other apps; report allocation errors normally.
        memory = os.sysconf("SC_PHYS_PAGES") * os.sysconf("SC_PAGE_SIZE")
        mx.set_memory_limit(int(memory * 0.72))
        started = time.monotonic()
        if self.loaded_model_id != entry["id"]:
            self.unload()
        editing = bool(references)
        if editing not in self.pipelines:
            shared = self.model
            self.model = load_model(
                entry, self.model_path(entry), edit=editing, shared=shared
            )
            self.loaded_model_id = entry["id"]
            self.pipelines[editing] = self.model
            if shared is None:
                self.model.callbacks.register(GenerationProgress(self))
        self.model = self.pipelines[editing]
        self.timings["load"] = time.monotonic() - started
        self.stage_started = time.monotonic()
        self.emit("progress", stage="encoding", message="Reading your prompt…")
        if references:
            parameters["image_paths"] = references
        generated = self.model.generate_image(**parameters)
        self.timings["decode"] = time.monotonic() - self.stage_started
        self.emit("progress", stage="saving", message="Saving your image…")
        image_id = str(uuid.uuid4())
        image_path = self.root / "Images" / f"{image_id}.png"
        temporary_path = image_path.with_suffix(".tmp")
        record = dict(
            id=image_id,
            modelID=entry["id"],
            modelName=entry["name"],
            modelRepo=entry["repo"],
            modelRevision=entry["revision"],
            runtimeVersion=importlib.metadata.version("mflux"),
            prompt=parameters["prompt"],
            seed=parameters["seed"],
            width=parameters["width"],
            height=parameters["height"],
            steps=parameters["num_inference_steps"],
            createdAt=datetime.datetime.now(datetime.timezone.utc).isoformat(),
            durationSeconds=round(time.monotonic() - started, 1),
            referenceCount=len(references),
        )
        metadata = PngImagePlugin.PngInfo()
        metadata.add_text("OpenPixel", json.dumps(record))
        save_started = time.monotonic()
        generated.image.save(temporary_path, format="PNG", pnginfo=metadata)
        temporary_path.replace(image_path)
        atomic_json(image_path.with_suffix(".json"), record)
        self.timings["save"] = time.monotonic() - save_started
        self.timings["total"] = time.monotonic() - request_started
        # Diagnostic-only, with no prompts or file paths in the timing event.
        self.emit(
            "timing",
            seconds={
                key: round(value, 3) for key, value in self.timings.items()
            },
            promptCacheHit=getattr(self.model, "prompt_cache_hit", False),
        )
        logging.getLogger("openpixel.performance").info(
            "request=%s timings=%s prompt_cache_hit=%s",
            self.request_id,
            self.timings,
            getattr(self.model, "prompt_cache_hit", False),
        )
        record["imagePath"] = str(image_path)
        self.emit("result", image=record)
        self.emit("done", message="Image saved to your library.")

    def handle(self, request: dict[str, Any]) -> None:
        self.request_id = str(request.get("requestID", ""))
        action = request.get("action")
        if action == "status":
            self.status()
            self.emit("done", message="Ready")
            return
        if action == "unload":
            self.unload()
            self.emit("done", message="Model unloaded. Memory released.")
            return
        entry = self.model_entry(request.get("modelID", ""))
        if action == "download":
            self.download(entry)
        elif action == "generate":
            self.generate(entry, request)
        elif action == "remove":
            self.unload()
            directory = self.model_path(entry)
            if directory.exists():
                shutil.rmtree(directory)
            self.status()
            self.emit("done", message="Model removed. Your images are kept.")
        else:
            raise ValueError("Unknown worker request.")


class GenerationProgress:
    """Reports completed GPU steps, then the final decode stage."""

    def __init__(self, worker: Worker) -> None:
        self.worker = worker

    def call_before_loop(self, **kwargs: Any) -> None:
        self.worker.timings["prepare"] = (
            time.monotonic() - self.worker.stage_started
        )
        self.worker.stage_started = time.monotonic()
        self.worker.emit(
            "progress",
            stage="generating",
            message="Creating your image…",
            progress=0,
        )

    def call_in_loop(
        self, t: int, latents: Any, config: Any, **kwargs: Any
    ) -> None:
        import mlx.core as mx

        mx.eval(latents)
        self.worker.emit(
            "progress",
            stage="generating",
            message=f"Step {t + 1} of {config.num_inference_steps}",
            progress=(t + 1) / config.num_inference_steps,
        )

    def call_after_loop(self, **kwargs: Any) -> None:
        self.worker.timings["denoise"] = (
            time.monotonic() - self.worker.stage_started
        )
        self.worker.stage_started = time.monotonic()
        self.worker.emit(
            "progress", stage="decoding", message="Developing the final image…"
        )


def main() -> None:
    # The app bundle is signed and may be read-only after installation.
    sys.dont_write_bytecode = True
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", required=True, type=pathlib.Path)
    arguments = parser.parse_args()
    os.environ["HF_HOME"] = str(arguments.root / "Cache" / "huggingface")
    os.environ["HF_HUB_OFFLINE"] = "1"
    os.environ["TRANSFORMERS_OFFLINE"] = "1"
    os.environ["HF_HUB_DISABLE_TELEMETRY"] = "1"
    os.environ["HF_HUB_DISABLE_XET"] = "1"
    os.environ["TOKENIZERS_PARALLELISM"] = "false"
    os.environ["MPLCONFIGDIR"] = str(arguments.root / "Cache" / "matplotlib")
    logging.basicConfig(level=logging.WARNING, stream=sys.stderr)
    logging.getLogger("openpixel.performance").setLevel(logging.INFO)
    worker = Worker(arguments.root)
    worker.emit("ready")
    # Third-party progress/logging must never contaminate protocol stdout.
    with contextlib.redirect_stdout(sys.stderr):
        for line in sys.stdin:
            worker.request_id = ""
            try:
                if len(line.encode()) > MAX_REQUEST_BYTES:
                    raise ValueError("Request is too large.")
                request = json.loads(line)
                if not isinstance(request, dict):
                    raise ValueError("Request must be a JSON object.")
                worker.handle(request)
            except Exception as error:
                # Process boundary: report failure and keep serving requests.
                logging.exception("Worker request failed")
                worker.unload()
                worker.status()
                worker.emit("error", message=str(error)[:1000])


if __name__ == "__main__":
    main()
