#!/bin/zsh
set -euo pipefail
BASE="$(cd "$(dirname "$0")" && pwd)"
PLIST="$HOME/Library/LaunchAgents/com.maan.connect.plist"
mkdir -p "$HOME/Library/LaunchAgents" "$HOME/Library/Logs"
cat > "$PLIST" <<EOF2
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple Computer//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>Label</key><string>com.maan.connect</string>
<key>ProgramArguments</key><array><string>$BASE/start_maan.sh</string></array>
<key>RunAtLoad</key><true/>
<key>KeepAlive</key><true/>
<key>ProcessType</key><string>Background</string>
<key>StandardOutPath</key><string>$HOME/Library/Logs/MAAN-launchagent.log</string>
<key>StandardErrorPath</key><string>$HOME/Library/Logs/MAAN-launchagent.error.log</string>
</dict></plist>
EOF2
launchctl bootout "gui/$(id -u)" "$PLIST" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST"
echo "MAAN auto-start installed: $PLIST"
