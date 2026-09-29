"""Storage and protocol checks that do not need model weights or a GPU."""

import hashlib
import io
import json
import pathlib
import subprocess
import sys
import tempfile
import types
import unittest
import weakref
from unittest import mock

from Worker import worker


class PromptCacheTest(unittest.TestCase):
    def setUp(self):
        self.core = types.ModuleType("mlx.core")
        self.core.eval = mock.Mock()
        mlx = types.ModuleType("mlx")
        mlx.core = self.core
        patch = mock.patch.dict(
            sys.modules, {"mlx": mlx, "mlx.core": self.core}
        )
        patch.start()
        self.addCleanup(patch.stop)

        class Encoder:
            def _encode_prompt_pair(self, **parameters):
                self.calls.append(parameters)
                return object(), object(), None, None

        class CachedEncoder(worker.CachedPromptEncoding, Encoder):
            def __init__(self):
                self.calls = []
                self.prompt_cache = {}

        self.encoder = CachedEncoder()

    def encode(self, prompt="lake", guidance=1.0):
        return self.encoder._encode_prompt_pair(
            prompt=prompt, negative_prompt=" ", guidance=guidance
        )

    def test_reuses_realized_values_and_respects_encoding_settings(self):
        first = self.encode()
        self.assertIs(self.encode(), first)
        self.assertTrue(self.encoder.prompt_cache_hit)
        self.core.eval.assert_called_once_with(first[0], first[1])
        self.assertIsNot(self.encode(guidance=2.0), first)
        self.assertFalse(self.encoder.prompt_cache_hit)

    def test_evicts_least_recently_used_prompt(self):
        first = self.encode("first")
        for prompt in ("second", "third", "fourth"):
            self.encode(prompt)
        self.assertIs(self.encode("first"), first)
        self.encode("fifth")
        self.assertEqual(len(self.encoder.prompt_cache), 4)
        self.assertIs(self.encode("first"), first)
        self.encode("second")
        self.assertFalse(self.encoder.prompt_cache_hit)
        self.assertEqual(len(self.encoder.prompt_cache), 4)

    def test_failed_evaluation_does_not_poison_cache(self):
        self.core.eval.side_effect = RuntimeError("allocation failed")
        with self.assertRaises(RuntimeError):
            self.encode()
        self.assertEqual(self.encoder.prompt_cache, {})
        self.core.eval.side_effect = None
        self.encode()
        self.assertFalse(self.encoder.prompt_cache_hit)

    def test_shared_variants_reuse_cache_but_other_models_do_not(self):
        first = self.encode()
        sibling = type(self.encoder)()
        sibling.prompt_cache = self.encoder.prompt_cache
        self.assertIs(
            sibling._encode_prompt_pair(
                prompt="lake", negative_prompt=" ", guidance=1.0
            ),
            first,
        )
        self.assertEqual(sibling.calls, [])
        self.encoder = type(self.encoder)()
        self.assertIsNot(self.encode(), first)


class GenerationValidationTest(unittest.TestCase):
    def test_zero_seed_is_preserved(self):
        parameters = worker.validate_generation(dict(prompt="A lake", seed=0))
        self.assertEqual(parameters["seed"], 0)

    def test_rejects_unsupported_or_dangerous_requests(self):
        invalid = [
            dict(prompt=" "),
            dict(prompt="x" * 4001),
            dict(prompt="x", width=8192),
            dict(prompt="x", steps=1000),
            dict(prompt="x", seed=-1),
            dict(prompt="x", seed=True),
            dict(prompt="x", seed=2**32),
        ]
        for request in invalid:
            with self.subTest(request=str(request)[:70]):
                with self.assertRaises(ValueError):
                    worker.validate_generation(request)


class ReferenceValidationTest(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.inputs = pathlib.Path(temporary.name) / "Inputs"
        self.inputs.mkdir()
        self.image = self.inputs / "reference.png"
        self.image.write_bytes(b"png")

    def test_accepts_images_in_inputs_directory(self):
        paths = worker.validate_references(
            dict(images=[str(self.image)]), self.inputs
        )
        self.assertEqual(paths, [str(self.image.resolve())])
        self.assertEqual(worker.validate_references({}, self.inputs), [])

    def test_rejects_unsafe_missing_or_excess_references(self):
        outside = self.inputs.parent / "outside.png"
        outside.write_bytes(b"png")
        invalid = [
            dict(images=str(self.image)),
            dict(images=[1]),
            dict(images=[str(outside)]),
            dict(images=[str(self.inputs / ".." / "outside.png")]),
            dict(images=[str(self.inputs / "missing.png")]),
            dict(images=[str(self.image)] * 4),
        ]
        for request in invalid:
            with self.subTest(request=str(request)[:70]):
                with self.assertRaises(ValueError):
                    worker.validate_references(request, self.inputs)


class StorageTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = pathlib.Path(self.temporary.name)
        self.output = io.StringIO()
        self.worker = worker.Worker(self.root, self.output)
        self.entry = self.worker.catalog[0]

    def test_unload_releases_both_variants_and_shared_cache(self):
        class Pipeline:
            pass

        generate, edit = Pipeline(), Pipeline()
        cached_value = Pipeline()
        generate.prompt_cache = edit.prompt_cache = {"prompt": cached_value}
        references = [
            weakref.ref(value) for value in (generate, edit, cached_value)
        ]
        self.worker.model = edit
        self.worker.pipelines = {False: generate, True: edit}
        self.worker.loaded_model_id = self.entry["id"]
        del generate, edit, cached_value
        self.worker.unload()
        self.assertTrue(all(reference() is None for reference in references))
        self.assertIsNone(self.worker.loaded_model_id)

    def test_download_resumes_bytes_and_verifies_the_result(self):
        entry = dict(self.entry, sizeBytes=6)
        item = dict(
            path="small.bin",
            size=6,
            sha256=hashlib.sha256(b"abcdef").hexdigest(),
        )
        local = self.worker.model_path(entry) / item["path"]
        local.parent.mkdir()
        partial = self.worker.partial_path(local, entry["revision"])
        partial.write_bytes(b"abc")
        response = mock.MagicMock()
        response.__enter__.return_value = response
        response.status_code = 206
        response.headers = {"Content-Range": "bytes 3-5/6"}
        response.iter_content.return_value = [b"def"]
        with mock.patch("requests.get", return_value=response) as request:
            self.worker.download_file(entry, item, 0)
        self.assertEqual(
            request.call_args.kwargs["headers"]["Range"], "bytes=3-"
        )
        self.assertEqual(local.read_bytes(), b"abcdef")
        self.assertFalse(partial.exists())

    def test_download_restarts_when_server_ignores_range(self):
        entry = dict(self.entry, sizeBytes=6)
        item = dict(
            path="small.bin",
            size=6,
            sha256=hashlib.sha256(b"abcdef").hexdigest(),
        )
        local = self.worker.model_path(entry) / item["path"]
        local.parent.mkdir()
        self.worker.partial_path(local, entry["revision"]).write_bytes(b"abc")
        response = mock.MagicMock()
        response.__enter__.return_value = response
        response.status_code = 200
        response.iter_content.return_value = [b"abcdef"]
        with mock.patch("requests.get", return_value=response):
            self.worker.download_file(entry, item, 0)
        self.assertEqual(local.read_bytes(), b"abcdef")

    def test_short_download_keeps_partial_file_for_retry(self):
        entry = dict(self.entry, sizeBytes=6)
        item = dict(path="small.bin", size=6)
        response = mock.MagicMock()
        response.__enter__.return_value = response
        response.status_code = 200
        response.iter_content.return_value = [b"abc"]
        with mock.patch("requests.get", return_value=response):
            with self.assertRaises(ValueError):
                self.worker.download_file(entry, item, 0)
        local = self.worker.model_path(entry) / item["path"]
        self.assertFalse(local.exists())
        self.assertEqual(
            self.worker.partial_path(local, entry["revision"]).read_bytes(),
            b"abc",
        )

    def test_partial_or_corrupt_model_is_not_installed(self):
        directory = self.worker.model_path(self.entry)
        directory.mkdir()
        worker.atomic_json(
            directory / "installed.json", dict(revision=self.entry["revision"])
        )
        self.assertFalse(self.worker.installed(self.entry))

    def test_integrity_failure_removes_bad_file(self):
        path = self.root / "corrupt.safetensors"
        path.write_bytes(b"bad")
        entry = dict(size=3, sha256=hashlib.sha256(b"yes").hexdigest())
        with self.assertRaises(ValueError):
            self.worker.verify_file(path, entry)
        self.assertFalse(path.exists())

    def test_removal_cannot_escape_catalog_and_keeps_images(self):
        image = self.root / "Images" / "keep.png"
        image.write_bytes(b"image")
        with self.assertRaises(ValueError):
            self.worker.handle(dict(action="remove", modelID="../../Images"))
        directory = self.worker.model_path(self.entry)
        directory.mkdir()
        (directory / "partial").write_bytes(b"partial")
        self.worker.handle(dict(action="remove", modelID=self.entry["id"]))
        self.assertFalse(directory.exists())
        self.assertTrue(image.exists())

    def test_history_skips_incomplete_images_and_corrupt_metadata(self):
        images = self.root / "Images"
        (images / "broken.json").write_text("{")
        (images / "missing.json").write_text(
            json.dumps(dict(id="missing", createdAt="2026-09-28"))
        )
        (images / "valid.png").write_bytes(b"image")
        record = dict.fromkeys(worker.HISTORY_STRINGS, "example")
        record.update(
            id="valid",
            createdAt="2026-09-28",
            seed=0,
            width=768,
            height=768,
            steps=4,
            durationSeconds=20.0,
        )
        worker.atomic_json(images / "valid.json", record)
        (images / "incomplete.png").write_bytes(b"image")
        worker.atomic_json(
            images / "incomplete.json",
            dict(id="incomplete", createdAt="2026-09-28"),
        )
        records = self.worker.history()
        self.assertEqual(len(records), 1)
        self.assertEqual(
            records[0]["imagePath"], str((images / "valid.png").resolve())
        )

    def test_status_events_preserve_request_id(self):
        self.worker.handle(dict(action="status", requestID="abc"))
        events = [
            json.loads(line) for line in self.output.getvalue().splitlines()
        ]
        self.assertEqual([e["event"] for e in events], ["status", "done"])
        self.assertTrue(all(e["requestID"] == "abc" for e in events))

    def test_process_recovers_after_invalid_request(self):
        requests = [
            dict(action="generate", modelID="unknown", requestID="bad"),
            dict(action="status", requestID="good"),
        ]
        result = subprocess.run(
            [
                sys.executable,
                "-I",
                "-B",
                str(pathlib.Path(worker.__file__)),
                "--root",
                str(self.root),
            ],
            input="\n".join(json.dumps(item) for item in requests) + "\n",
            text=True,
            capture_output=True,
            timeout=10,
            check=True,
        )
        events = [json.loads(line) for line in result.stdout.splitlines()]
        self.assertTrue(
            any(
                event["event"] == "error" and event["requestID"] == "bad"
                for event in events
            )
        )
        self.assertEqual(events[-1]["event"], "done")
        self.assertEqual(events[-1]["requestID"], "good")


if __name__ == "__main__":
    unittest.main()
