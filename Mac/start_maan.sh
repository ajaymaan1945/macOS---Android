#!/bin/zsh
set -euo pipefail
BASE="$(cd "$(dirname "$0")" && pwd)"
LOG_DIR="$HOME/Library/Logs"
mkdir -p "$LOG_DIR"

# Start exactly one local MAAN transport server.
if ! pgrep -f "${BASE}/MAANServer/server.py" >/dev/null 2>&1; then
  nohup python3 "$BASE/MAANServer/server.py" >>"$LOG_DIR/MAAN-server.log" 2>&1 &
fi

# Start the menu-bar companion if it has already been built.
if [[ -x "$BASE/MAAN.app/Contents/MacOS/MAAN" ]]; then
  if ! pgrep -f "$BASE/MAAN.app/Contents/MacOS/MAAN" >/dev/null 2>&1; then
    open "$BASE/MAAN.app" >/dev/null 2>&1 || true
  fi
fi

# Keep this LaunchAgent alive; the server/app themselves are separately guarded.
while true; do
  sleep 30
  if ! pgrep -f "${BASE}/MAANServer/server.py" >/dev/null 2>&1; then
    nohup python3 "$BASE/MAANServer/server.py" >>"$LOG_DIR/MAAN-server.log" 2>&1 &
  fi
  if [[ -x "$BASE/MAAN.app/Contents/MacOS/MAAN" ]] && ! pgrep -f "$BASE/MAAN.app/Contents/MacOS/MAAN" >/dev/null 2>&1; then
    open "$BASE/MAAN.app" >/dev/null 2>&1 || true
  fi
done
