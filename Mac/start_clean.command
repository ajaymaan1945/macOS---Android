#!/bin/zsh
set -euo pipefail
BASE="$(cd "$(dirname "$0")" && pwd)"
cd "$BASE"
if [[ -x .venv/bin/python ]]; then PY=.venv/bin/python; else PY=python3; fi
if ! pgrep -f "${BASE}/MAANServer/server.py" >/dev/null 2>&1; then
  nohup "$PY" "$BASE/MAANServer/server.py" >>"$HOME/Library/Logs/MAAN-server.log" 2>&1 &
  sleep 1
fi
if [[ -x "$BASE/MAAN.app/Contents/MacOS/MAAN" ]]; then open "$BASE/MAAN.app"; else echo "MAAN.app is not built. Run build_maan.command first."; fi
