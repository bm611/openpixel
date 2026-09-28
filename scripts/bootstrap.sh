#!/bin/bash
# Development setup only. End users receive this runtime inside OpenPixel.app.
set -euo pipefail
cd "$(dirname "$0")/.."
command -v uv >/dev/null || { echo "Install uv first: https://docs.astral.sh/uv/" >&2; exit 1; }
export UV_CACHE_DIR="$PWD/.build/uv-cache"
export UV_PYTHON_INSTALL_DIR="$PWD/.build/python"
export UV_LINK_MODE=copy
runtime="$PWD/.build/runtime"
lock_hash="$(shasum -a 256 Worker/requirements.lock | cut -d ' ' -f 1)"
if [[ -x "$runtime/bin/python3.12" && -f "$runtime/.openpixel-lock" ]] && [[ "$(cat "$runtime/.openpixel-lock")" == "$lock_hash" ]]; then
    echo "Bundled runtime is ready."
    exit 0
fi
uv python install 3.12.13
if [[ ! -x "$runtime/bin/python3.12" ]]; then
    ditto "$UV_PYTHON_INSTALL_DIR/cpython-3.12.13-macos-aarch64-none" "$runtime"
fi
# This is an app-owned copy of standalone Python, never the system interpreter.
uv pip sync --python "$runtime/bin/python3.12" --break-system-packages Worker/requirements.lock
printf '%s' "$lock_hash" > "$runtime/.openpixel-lock"
echo "Bundled runtime is ready."

