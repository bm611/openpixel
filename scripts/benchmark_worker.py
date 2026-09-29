"""Compares worker revisions on real hardware using isolated image libraries.

Run with the bundled Python and --baseline-ref pointing at the old revision.
Requires the installed Klein 4B model and Metal access. No downloads are made.
Artifacts and timings are saved under .build/performance, never the app library.
"""

import argparse
import contextlib
import gc
import hashlib
import io
import json
import os
import pathlib
import shutil
import subprocess
import sys
import time
import types
import uuid


PROJECT = pathlib.Path(__file__).resolve().parents[1]


def load_worker(source: str) -> types.ModuleType:
    """Loads a worker revision with the current pinned catalog location."""
    module = types.ModuleType("benchmark_worker_revision")
    module.__file__ = str(PROJECT / "Worker" / "worker.py")
    exec(compile(source, module.__file__, "exec"), module.__dict__)
    return module


def run_suite(module, root, model_dir, reference=None):
    """Exercises cold, repeated-prompt, and bidirectional mode switches."""
    import mlx.core as mx
    from PIL import Image

    output = io.StringIO()
    worker = module.Worker(root, output)
    entry = worker.model_entry("flux2-klein-4b")
    worker.model_path(entry).symlink_to(model_dir, target_is_directory=True)
    results = []
    prompt = "A small red sailboat on a quiet lake, soft morning light."
    reference_path = root / "Cache" / "Inputs" / "reference.png"
    cases = [
        ("cold", prompt, False),
        ("repeat_prompt", prompt, False),
        ("switch_to_edit", "Make the sailboat blue.", True),
        ("switch_to_generate", prompt, False),
    ]
    for name, text, editing in cases:
        output.seek(0)
        output.truncate()
        mx.reset_peak_memory()
        started = time.perf_counter()
        with contextlib.redirect_stdout(sys.stderr):
            worker.handle(
                dict(
                    action="generate",
                    requestID=name,
                    modelID=entry["id"],
                    prompt=text,
                    seed=42,
                    steps=4,
                    width=768,
                    height=768,
                    images=[str(reference_path)] if editing else [],
                )
            )
        elapsed = time.perf_counter() - started
        events = [json.loads(line) for line in output.getvalue().splitlines()]
        record = next(e["image"] for e in events if e["event"] == "result")
        with Image.open(record["imagePath"]) as image:
            digest = hashlib.sha256(image.tobytes()).hexdigest()
        timing = next((e for e in events if e["event"] == "timing"), {})
        result = dict(
            case=name,
            seconds=round(elapsed, 3),
            pixelSHA256=digest,
            peakGB=round(mx.get_peak_memory() / 1024**3, 3),
            timing=timing,
        )
        results.append(result)
        print(json.dumps(dict(suite=root.name, **result)), flush=True)
        if name == "cold":
            shutil.copyfile(reference or record["imagePath"], reference_path)
        if hasattr(worker, "pipelines") and len(worker.pipelines) == 2:
            generate, edit = worker.pipelines[False], worker.pipelines[True]
            for attribute in (
                "vae",
                "transformer",
                "text_encoder",
                "prompt_cache",
            ):
                if getattr(generate, attribute) is not getattr(edit, attribute):
                    raise AssertionError(f"Not shared: {attribute}")
            del generate, edit
    worker.unload()
    if getattr(worker, "pipelines", None):
        raise AssertionError("Unload retained pipelines")
    del worker
    gc.collect()
    mx.clear_cache()
    return results, reference_path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--baseline-ref", required=True)
    parser.add_argument(
        "--model-dir",
        type=pathlib.Path,
        default=pathlib.Path.home()
        / "Library/Application Support/OpenPixel/Models/flux2-klein-4b",
    )
    args = parser.parse_args()
    model_dir = args.model_dir.resolve()
    if not (model_dir / "installed.json").is_file():
        parser.error("An installed Klein 4B model is required")
    root = PROJECT / ".build" / "performance" / str(uuid.uuid4())
    root.mkdir(parents=True)
    for key in (
        "HF_HUB_OFFLINE",
        "TRANSFORMERS_OFFLINE",
        "HF_HUB_DISABLE_TELEMETRY",
    ):
        os.environ[key] = "1"
    os.environ["TOKENIZERS_PARALLELISM"] = "false"
    os.environ["MPLCONFIGDIR"] = str(root / "matplotlib")
    # Both suites start with warm imports, but no model loaded. This comparison
    # measures model loading and generation, not process/import startup.
    from mflux.models.flux2 import variants  # noqa: F401

    baseline_source = subprocess.run(
        ["git", "show", f"{args.baseline_ref}:Worker/worker.py"],
        cwd=PROJECT,
        capture_output=True,
        text=True,
        check=True,
    ).stdout
    baseline, reference = run_suite(
        load_worker(baseline_source),
        root / "baseline",
        model_dir,
    )
    optimized, _ = run_suite(
        load_worker((PROJECT / "Worker/worker.py").read_text()),
        root / "optimized",
        model_dir,
        reference,
    )
    identical = all(
        before["pixelSHA256"] == after["pixelSHA256"]
        for before, after in zip(baseline, optimized, strict=True)
    )
    report = dict(
        baseline=baseline, optimized=optimized, identicalPixels=identical
    )
    (root / "report.json").write_text(json.dumps(report, indent=2))
    print(f"Report: {root / 'report.json'}", flush=True)
    if not identical:
        raise AssertionError("Output pixels differ from baseline")


if __name__ == "__main__":
    main()
