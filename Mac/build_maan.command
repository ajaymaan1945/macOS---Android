#!/bin/zsh
set -euo pipefail
BASE="$(cd "$(dirname "$0")" && pwd)"
cd "$BASE"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "MAAN must be built on macOS."
  exit 1
fi

if ! command -v xcrun >/dev/null 2>&1; then
  echo "Xcode Command Line Tools are missing. Run: xcode-select --install"
  exit 1
fi

APP="$BASE/MAAN.app"
BUILD="$BASE/.build"
BIN="$BUILD/release/MAAN"

printf '\n=== MAAN CLEAN BUILD ===\n'
echo "Source: $BASE/Sources/MAAN/main.swift"
echo "Toolchain: $(xcrun swiftc --version | head -1)"

echo "[1/4] Removing stale build..."
rm -rf "$BUILD" "$APP"

echo "[2/4] Verifying AppKit import..."
head -n 6 "$BASE/Sources/MAAN/main.swift"
grep -qx 'import AppKit' "$BASE/Sources/MAAN/main.swift"

echo "[3/4] Compiling Swift Package with AppKit linked explicitly..."
xcrun swift build -c release

echo "[4/4] Creating app bundle..."
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/MAAN"
cp "$BASE/Info.plist" "$APP/Contents/Info.plist"
cp "$BASE/Resources/ring.wav" "$APP/Contents/Resources/ring.wav"
chmod +x "$APP/Contents/MacOS/MAAN"
codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || true

xattr -dr com.apple.quarantine "$APP" 2>/dev/null || true

echo
echo "BUILD SUCCESSFUL"
echo "$APP"
open "$APP"
