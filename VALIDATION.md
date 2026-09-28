# Validation — 28 September 2026

Environment: Apple M3 Pro, 18 GB unified memory, macOS 26.6.2, Swift 6.3.3.
Runtime: bundled CPython 3.12.13, mflux 0.20.0, MLX 0.32.2.

## Completed

- Swift debug and release builds compiled successfully.
- Downloaded all 4,619,700,117 bytes of the pinned model; verified expected sizes
  and SHA-256 hashes for Hugging Face LFS files before marking it installed.
- Generated a real 768 × 768 image, four steps, seed 42: **22.5 seconds**.
- Generated a second 768 × 768 image through the native app and its bundled
  runtime: approximately **29 seconds**.
- Generated a 1024 × 768 landscape, four steps, seed 21, with `sandbox-exec`
  denying all network access to the bundled worker: **32.0 seconds**.
- Inspected the native window and its progress states through accessibility
  and a screenshot. Viewed the completed image in the app's gallery.
- Cancelled a running generation through the UI and observed recovery to Ready
  with existing images preserved and Generate enabled.
- Checked the empty-model first-run flow and download cancellation in the native
  model sheet. Confirmed the action changes to Resume Download.
- Verified real HTTP byte resume against Hugging Face: a 1,048,576-byte partial
  tokenizer file resumed with HTTP 206 and `Content-Range` starting at 1,048,576.
  The completed 11,422,650-byte file passed its SHA-256 check. The app owns stable
  revision-specific `.part` files because the pinned Hub client's temporary
  download files do not survive cancellation in a reusable form.
- Exported a generated PNG through the native Save As dialog.
- Confirmed the bundled interpreter resolves its standard library and packages
  inside the `.app`, independently of the development interpreter.
- Verified the local app signature with `codesign --verify --deep --strict`.
- Eleven focused worker tests cover parameter bounds, seed zero, partial model
  state, checksum failure, safe model removal, damaged history, request IDs,
  process recovery after a failed request, byte-range resume, servers ignoring
  Range headers, and preservation of truncated downloads.
- Ruff lint and formatting checks passed.

Timings are individual runs, measured from model loading through generation;
they are not a benchmark or a performance guarantee. Process/import startup
and PNG writing are outside the reported worker generation duration.

## Remaining release checks

- Installation and runtime behavior on a second, clean Mac.
- Behavior across other supported macOS versions and memory sizes.
- Developer ID signing and Apple notarization for public distribution.
- Z-Image Turbo and FLUX.2 Klein 9B are in the catalog
  with pinned revisions and hashes, but have not been downloaded or run yet.
- Qwen and other model families are not included in this version.
