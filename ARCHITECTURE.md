# OpenPixel Architecture

OpenPixel is a macOS SwiftUI app that generates and edits images locally on
Apple Silicon. The UI lives in `App/` (Swift). Inference, model downloads and
library storage live in a bundled Python process in `Worker/`. The two talk
over a line-delimited JSON protocol on stdin/stdout.

```
SwiftUI views -> AppStore -> WorkerClient --stdin (JSON lines)--> worker.py
     ^             (state)    (Process)   <--stdout (JSON lines)--   |
     +--- @Observable updates ---+                                  +-> mflux / MLX
                                                    <root>/{Models,Images,Logs,Cache}
```

## App (`App/`)

| File | Role |
| --- | --- |
| `OpenPixelApp.swift` | `@main` entry, window and menu setup, `AppDelegate` (shuts the worker down on quit). |
| `AppStore.swift` | Single `@Observable` source of truth: prompt, aspect, model selection, references, current `Operation`, progress, errors, history. Builds requests and applies worker events. |
| `WorkerClient.swift` | Owns the worker `Process`, pipes and log file. Sends requests, decodes events, handles cancel and shutdown. |
| `Models.swift` | `WorkerEvent`, `ModelInfo`, `ModelStatus`, `GeneratedImage`, `AspectRatio`, `Operation`, `AppFailure`, `AppPaths`. |
| `ContentView.swift` | Main layout: canvas, library strip, progress/status. |
| `PromptComposer.swift` | Prompt field, presets, attachments, aspect and step controls. |
| `ModelsView.swift` | Model catalog UI (download, resume, remove) and `ImageInfoView`. |
| `LibraryView.swift` | Grid of generated images. |
| `Presets.swift` | Style presets applied to prompts. |
| `Components.swift` | `Palette`, buttons, pills, glyphs, `ImageCache`. |
| `SystemMonitor.swift` | Samples CPU and memory use for the status display. |

`AppPaths` resolves the data root to `~/Library/Application Support/OpenPixel`,
or `$OPENPIXEL_DATA_DIR` if set. Subfolders are `Models/`, `Images/`, `Logs/`
and `Cache/Inputs/`.

## Worker (`Worker/`)

- `worker.py`: the `Worker` class. It owns storage, the model catalog, and at
  most one loaded model, and serves requests one at a time.
- `catalog.json`: revision-pinned model list (id, architecture, Hugging Face
  repo and revision, file sizes and SHA-256, default steps, `supportsEditing`).
  Currently FLUX.2 Klein 4B, FLUX.2 Klein 9B and Z-Image Turbo.
- `requirements.lock`: pinned Python dependencies for the bundled runtime.

At runtime the app launches `Resources/Runtime/bin/python3.12 -I -B -u
Resources/Worker/worker.py --root <data root>`. It strips `PYTHONHOME`,
`PYTHONPATH` and `VIRTUAL_ENV`, and sends stderr to `Logs/worker.log`. This
runtime is produced by `scripts/build.sh`.

## Protocol

Transport: one JSON object per line. The worker reserves stdout for protocol
events. During request handling, stdout is redirected to stderr so library
output cannot corrupt the stream. Requests are capped at 64 KB.

Requests (App -> Worker). Every request carries `action`, `requestID` and
`modelID`.

| `action` | Extra fields | Effect |
| --- | --- | --- |
| `status` | none | Emits installed/partial state per model plus image history. |
| `download` | none | Resumable, hash-verified download from the pinned HF revision. |
| `generate` | `prompt`, `width`, `height`, `steps`, `seed?`, `images?` | Runs inference and saves a PNG with a JSON sidecar. |
| `remove` | none | Deletes model weights and keeps generated images. |
| `unload` | none | Drops the loaded model and clears the MLX cache. |

Events (Worker -> App), decoded as `WorkerEvent`. Each carries `event` and
`requestID`.

- `ready`: emitted once at startup.
- `progress`: `stage` (downloading, verifying, loading, encoding, generating,
  decoding, saving), `message`, `progress` (0-1), and byte counts for downloads.
- `status`: `models[]` and `history[]` (each with `imagePath`).
- `result`: the saved `image` record.
- `done`: the request finished successfully, with a `message`.
- `error`: a `message` for the user. The worker unloads the model, re-emits
  `status`, and keeps serving.

## Request lifecycle

1. A view calls an `AppStore` method such as `generate()`. `AppStore.send` is a
   no-op while another `Operation` is in flight (one request at a time).
2. It sets `operation`, builds the request with a fresh `requestID`, and calls
   `WorkerClient.send`. The worker is started lazily if it is not running.
3. A reader `Task` in `WorkerClient` decodes each stdout line and calls
   `onEvent`, and `AppStore.receive` updates progress, models and history.
4. `done` or `error` returns the store to `.idle`. After a generation, an idle
   timer sends `unload` after 120 s to release GPU memory.

## Safety and lifecycle

- Validation happens in the worker before any model load: prompt length,
  allowed sizes (768x768, 1024x768, 768x1024), steps 1-8, seed range, and up to
  3 reference images.
- Reference images must live directly in `Cache/Inputs/`. The app imports them
  as PNGs of at most 1024 px, and the worker rejects any other path.
- The worker sets an MLX memory limit of 72% of RAM and checks free disk space
  before downloads (+1 GB) and generation (100 MB).
- Cancel: `WorkerClient.cancel()` sends SIGTERM, then SIGKILL after 2 s. The
  next request restarts the worker. Quit sends SIGKILL immediately to free GPU
  memory.
- Unexpected worker exit or EOF calls `onExit`, and the UI shows an error. The
  worker restarts automatically on the next request.
- The model cache is offline-only (`HF_HUB_OFFLINE=1`). Only the `download`
  action touches the network, using the pinned revision and sizes from the
  catalog.
- History is stored on disk as `Images/<id>.png` plus `<id>.json`. Invalid
  records are ignored.
