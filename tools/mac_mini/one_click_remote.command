#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SETUP_SCRIPT="${ROOT_DIR}/tools/mac_mini/setup_codex_access.command"
START_SCRIPT="${ROOT_DIR}/tools/mac_mini/start_remote_site.command"

chmod +x "${SETUP_SCRIPT}" "${START_SCRIPT}"

echo "==> Step 1/2: enabling SSH access and keeping the Mac mini awake"
"${SETUP_SCRIPT}"

echo
echo "==> Step 2/2: starting the local Wi-Fi remote site"
exec "${START_SCRIPT}"
