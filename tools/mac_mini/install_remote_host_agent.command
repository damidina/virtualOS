#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
INSTALL_SCRIPT="${ROOT_DIR}/tools/mac_mini/install_remote_host_agent.sh"

chmod +x "${INSTALL_SCRIPT}"
exec "${INSTALL_SCRIPT}"
