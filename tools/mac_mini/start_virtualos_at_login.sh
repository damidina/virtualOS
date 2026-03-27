#!/usr/bin/env bash

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ENV_FILE="${HOME}/.config/virtualos/start.env"
LOG_FILE="${HOME}/Library/Logs/virtualos-startup.log"

mkdir -p "$(dirname "$ENV_FILE")"
mkdir -p "$(dirname "$LOG_FILE")"

exec >>"$LOG_FILE" 2>&1

echo "[$(date '+%Y-%m-%d %H:%M:%S')] starting virtualOS login hook"

if [[ -f "$ENV_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$ENV_FILE"
fi

if [[ -z "${VOS_VM_PASSWORD:-}" ]]; then
  echo "VOS_VM_PASSWORD is not set. Refusing to run start.sh unattended."
  exit 1
fi

cd "$REPO_DIR"
exec "$REPO_DIR/start.sh"
