# OpenPixel

A small native macOS studio for local image generation. SwiftUI provides the
interface; a bundled Python worker runs FLUX.2 Klein through MLX. No accounts,
cloud generation, local web server, or user-installed Python are needed.

## Run the app

Open `dist/OpenPixel.app`. You can move it to your Applications folder.

1. Open **Manage models** and download FLUX.2 Klein (4.62 GB).
2. Describe an image, choose a shape, and click **Generate** (`⌘Return`).
3. Results save automatically. Use **Save As** (`⌘S`) to export a PNG, or
   **Reveal in Finder** to locate the original.

The model is already downloaded on the development Mac, and three sample images
were generated during validation. Other Macs download their own model weights.

### Requirements

- Apple Silicon Mac; macOS 14 or later (tested on macOS 26.6.2).
- 16 GB or more unified memory recommended. The tested machine has an M3 Pro
  and 18 GB. This recommendation is not a guarantee for every workload.
- Approximately 1.1 GB for the app, 4.62 GB for the model, and space for images.
- Internet for the initial model download. Generation then works offline.

This build uses a local ad hoc signature. It is ready for use on this Mac;
public distribution still needs Developer ID signing, notarization, and testing
on another Mac. Do not treat the current bundle as an App Store release.

## Included in v0.1

- Native window with prompt editor, large preview, and recent image strip.
- Square (768 × 768), landscape (1024 × 768), and portrait (768 × 1024).
- Seed control and 1–8 generation steps; the default is four.
- Revision-pinned, resumable Hugging Face downloads with checksums for large
  model files and checks for available disk space.
- Progress for model loading, prompt encoding, generation, decoding, and saving.
- Cancellation stops the worker and releases GPU memory; a fresh worker starts
  automatically. Interrupted downloads can resume.
- One loaded model, one job at a time. Model memory unloads after two idle minutes.
- Local image history; prompt/settings reuse; PNG metadata and JSON sidecars.
- Native PNG export, Finder integration, model removal, and error reporting.
- Bundled Python 3.12.13, mflux 0.20.0, and pinned dependencies.

The initial catalog contains **FLUX.2 Klein 4B, 4-bit**. Qwen, LoRAs, image editing,
batch queues, arbitrary model imports, and other runtimes are future work.

## Storage and privacy

All app data lives in `~/Library/Application Support/OpenPixel/`:

```text
Models/     Downloaded model weights and resumable download state
Images/     PNG files and JSON generation records
Logs/       Worker diagnostics
Cache/      Runtime caches
```

Models are downloaded from Hugging Face and its file delivery infrastructure.
The worker disables Hugging Face telemetry and implicit token use. It loads
local files for generation with Hugging Face and Transformers offline modes
enabled. There is no OpenPixel server or analytics service.

Every saved PNG includes an `OpenPixel` metadata record with its prompt, seed,
dimensions, steps, model repository/revision, runtime version, and generation
duration. Exported PNGs retain that metadata. Reusing these settings is useful
for iteration; identical output across different runtimes/hardware is not promised.

## Build from source

Development tools: Xcode with Swift 6.2 or later, Apple command line tools, and
[uv](https://docs.astral.sh/uv/). No Python installation is required.

```sh
bash scripts/build.sh
open dist/OpenPixel.app
```

The first build downloads a standalone CPython interpreter into `.build/`,
copies it into a private runtime, and installs `Worker/requirements.lock` there.
It does not modify system Python. Subsequent builds reuse that runtime when the
lockfile is unchanged. The build packages it into the app, generates the icon,
and applies and verifies a local signature.

Open `Package.swift` in Xcode to edit the native code. The complete app must be
packaged by `scripts/build.sh` to include its worker and runtime resources.

## Architecture

```text
SwiftUI AppStore → WorkerClient → bundled Python worker → mflux / MLX / Metal
                    JSON lines       ├── model downloads
                    stdin/stdout     └── images + metadata
```

`App/` contains the UI, observable state, and process lifecycle. `Worker/worker.py`
owns model loading and storage. `Worker/catalog.json` pins model file paths,
sizes, checksums, and revision. The single worker stays alive for consecutive
jobs; cancellation terminates it. Standard output carries only protocol events,
while library output goes to the log. The app invokes Python in isolated mode
with bytecode writing disabled so the signed bundle stays immutable.

The protocol accepts `status`, `download`, `generate`, `remove`, and `unload`.
Requests have a `requestID`; all corresponding events preserve it. Responses
include `progress`, `status`, `result`, `done`, and `error`. This boundary keeps
the native UI independent of mflux's Python API.

## Verification

```sh
.build/runtime/bin/python3.12 -m unittest discover -s tests -v
ruff check Worker/worker.py tests/test_worker.py
ruff format --check --line-length 80 Worker/worker.py tests/test_worker.py
codesign --verify --deep --strict dist/OpenPixel.app
```

See [VALIDATION.md](VALIDATION.md) for actual generation timings and the checked
flows. `OPENPIXEL_DATA_DIR=/absolute/path` can isolate app data during development.

## Model and runtime sources

- [mflux](https://github.com/mflux-community/mflux) — MLX inference implementation.
- [MLX model weights](https://huggingface.co/mlx-community/flux2-klein-4b-4bit) —
  the catalog pins revision `860e87183ceb29e39627c0612ebd66d8ea66e68c`.
- [Original FLUX.2 Klein model](https://huggingface.co/black-forest-labs/FLUX.2-klein-4B).
- [Python standalone builds](https://github.com/astral-sh/python-build-standalone).

Dependency license files ship in the bundled Python distribution and its
`site-packages/*.dist-info` directories. Model weights download separately and
remain subject to their model license; this model is listed as Apache 2.0.

