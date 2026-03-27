#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BOOTSTRAP_SCRIPT="${ROOT_DIR}/tools/mac_mini/bootstrap.sh"
PUBLIC_KEY="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHUK3W2u6VKiDX3ORRwaF8ZA5Yp3z2IkWpwsuMbQltPa codex-macmini"

chmod +x "${BOOTSTRAP_SCRIPT}"

echo "==> Granting Codex SSH access and making this Mac mini reachable..."
"${BOOTSTRAP_SCRIPT}" \
  --ssh-public-key "${PUBLIC_KEY}" \
  --enable-remote-login \
  --disable-sleep

echo
echo "Done."
echo "This Mac mini should now accept Codex SSH access for the current user."
echo "You can close this Terminal window."
