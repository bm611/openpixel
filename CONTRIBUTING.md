# Contributing to OpenPixel

Thanks for helping out. OpenPixel is a native SwiftUI macOS app that talks to a
single bundled Python worker. Keep changes small and focused.

## Requirements

- Apple Silicon Mac, macOS 14 or later.
- Xcode with Swift 6.2 or later, and the Apple command line tools.
- [uv](https://docs.astral.sh/uv/). You do not need a system Python.

## Build and run

```sh
bash scripts/build.sh
open dist/OpenPixel.app
```

The first build downloads a standalone Python runtime into `.build/` and
installs the pinned worker dependencies (`Worker/requirements.lock`). It then
packages the app and verifies its local signature. Later builds reuse the
runtime if the lockfile is unchanged.

To iterate on the UI, open `Package.swift` in Xcode. Use the build script
whenever you need the worker and runtime packaged too.

Set `OPENPIXEL_DATA_DIR=/absolute/path` to keep development data (models,
images, logs) away from `~/Library/Application Support/OpenPixel/`.

## Project layout

```text
App/        SwiftUI app (single executable target in Package.swift)
  AppStore.swift, Models.swift     State and data types
  WorkerClient.swift               JSON-lines client for the worker
  ContentView, PromptComposer,
  LibraryView, ModelsView          Main views
  Presets.swift                    Style presets
Worker/     Python worker: worker.py, catalog.json (model catalog),
            requirements.lock (pinned dependencies)
scripts/    build.sh, bootstrap.sh, make_dmg.sh, make_icon.swift
tests/      test_worker.py (worker unit tests)
docs/       README screenshots
VALIDATION.md  Tested workflows and timings
```

The app and worker exchange JSON lines. If you change a request or response,
update both `WorkerClient.swift` and `Worker/worker.py`.

## Validate your changes

Run these before opening a pull request:

```sh
.build/runtime/bin/python3.12 -m unittest discover -s tests -v
ruff check Worker/worker.py tests/test_worker.py
ruff format --check --line-length 80 Worker/worker.py tests/test_worker.py
codesign --verify --deep --strict dist/OpenPixel.app
```

Also confirm that `bash scripts/build.sh` succeeds. For UI or generation
changes, launch the app and exercise the affected flow by hand (prompt,
generate, cancel, model download, edit).

[VALIDATION.md](VALIDATION.md) records what has been tested and on what
hardware. If you test something new, such as another model or macOS version,
add a dated note with your environment. Treat timings as single runs.

## Pull requests

- Add or update worker tests for any worker behavior change.
- Keep Python lines to 80 characters and run `ruff format`.
- Use short, imperative commit messages with a prefix, for example
  `docs: Add CONTRIBUTING guide`.
- Describe what you tested and on which Mac.
