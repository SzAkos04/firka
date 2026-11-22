#!/bin/zsh
# Installs (or removes with --remove) the launchd job that runs renew-on-iphone.sh at 9:00 and 19:00.
# launchd runs a missed time as soon as the Mac wakes up.
set -euo pipefail
LABEL=local.firka-ios.renew
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
SCRIPT=${0:A:h}/renew-on-iphone.sh

launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
if [[ ${1:-} == --remove ]]; then rm -f "$PLIST"; echo "removed"; exit 0; fi

mkdir -p "$HOME/Library/LaunchAgents"
cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key><string>$LABEL</string>
	<key>ProgramArguments</key><array><string>/bin/zsh</string><string>-c</string><string>'$SCRIPT'; '$SCRIPT' other</string></array>
	<key>StartCalendarInterval</key>
	<array>
		<dict><key>Hour</key><integer>9</integer><key>Minute</key><integer>0</integer></dict>
		<dict><key>Hour</key><integer>19</integer><key>Minute</key><integer>0</integer></dict>
	</array>
	<key>StandardErrorPath</key><string>$HOME/Library/Logs/firka-renew.log</string>
</dict>
</plist>
EOF
launchctl bootstrap "gui/$(id -u)" "$PLIST"
echo "installed: $PLIST"
