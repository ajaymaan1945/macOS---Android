#!/bin/zsh
set -euo pipefail
BASE="$(cd "$(dirname "$0")" && pwd)"
cd "$BASE"
if [[ "$(uname -s)" != "Darwin" ]]; then echo "Run on macOS."; exit 1; fi
PY="$(command -v python3 || true)"
if [[ -z "$PY" ]]; then echo "python3 not found."; exit 1; fi
if [[ ! -d .venv ]]; then "$PY" -m venv .venv; fi
.venv/bin/python -m pip install --upgrade pip
.venv/bin/python -m pip install -r requirements.txt

echo "Server environment ready."
