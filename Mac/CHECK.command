#!/bin/zsh
set -euo pipefail
BASE="$(cd "$(dirname "$0")" && pwd)"
cd "$BASE"

echo "=== MAAN SOURCE CHECK ==="
echo ""
echo "1) Swift source:"
echo "$BASE/Sources/MAAN/main.swift"
echo ""
head -n 6 "$BASE/Sources/MAAN/main.swift"
if grep -qx 'import AppKit' "$BASE/Sources/MAAN/main.swift"; then
  echo "OK: AppKit import is present."
else
  echo "ERROR: AppKit import is missing."
  exit 1
fi

echo ""
echo "2) Package.swift AppKit linker:"
grep 'linkedFramework("AppKit")' Package.swift

echo ""
echo "3) Swift parser check:"
xcrun swiftc -frontend -parse "$BASE/Sources/MAAN/main.swift"
echo "OK: Swift parser accepted the source."
