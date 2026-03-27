#!/usr/bin/env bash

set -euo pipefail

LABEL="com.github.yep.virtualos.start"
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PLIST_DIR="${HOME}/Library/LaunchAgents"
PLIST_PATH="${PLIST_DIR}/${LABEL}.plist"
WRAPPER_PATH="${REPO_DIR}/tools/mac_mini/start_virtualos_at_login.sh"
ENV_FILE="${HOME}/.config/virtualos/start.env"
LOG_OUT="${HOME}/Library/Logs/virtualos-startup.log"
LOG_ERR="${HOME}/Library/Logs/virtualos-startup.err.log"

mkdir -p "$PLIST_DIR"
mkdir -p "$(dirname "$ENV_FILE")"
mkdir -p "$(dirname "$LOG_OUT")"

cat > "$PLIST_PATH" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>${LABEL}</string>
  <key>ProgramArguments</key>
  <array>
    <string>${WRAPPER_PATH}</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>LimitLoadToSessionType</key>
  <array>
    <string>Aqua</string>
  </array>
  <key>WorkingDirectory</key>
  <string>${REPO_DIR}</string>
  <key>StandardOutPath</key>
  <string>${LOG_OUT}</string>
  <key>StandardErrorPath</key>
  <string>${LOG_ERR}</string>
</dict>
</plist>
EOF

chmod 644 "$PLIST_PATH"
chmod +x "$WRAPPER_PATH"

if [[ ! -f "$ENV_FILE" ]]; then
  cat > "${ENV_FILE}.example" <<'EOF'
VOS_VM_PASSWORD=replace-me
EOF
fi

launchctl unload "$PLIST_PATH" >/dev/null 2>&1 || true
launchctl load "$PLIST_PATH"

echo "Installed LaunchAgent: $PLIST_PATH"
echo "Wrapper script: $WRAPPER_PATH"
echo "Logs:"
echo "  $LOG_OUT"
echo "  $LOG_ERR"
echo
echo "If you have not created it yet, add:"
echo "  $ENV_FILE"
echo "with:"
echo "  VOS_VM_PASSWORD=..."
