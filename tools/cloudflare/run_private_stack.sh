#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SERVER_SCRIPT="${ROOT_DIR}/tools/virtualos_stream_server/server.py"

HOST="${HOST:-127.0.0.1}"
PORT="${PORT:-8899}"
TARGET_APP="${TARGET_APP:-Codex}"
CF_TUNNEL_CONFIG="${CF_TUNNEL_CONFIG:-${HOME}/.cloudflared/virtualos-remote.yml}"

if [[ -z "${VOS_AUTH_TOKEN:-}" ]]; then
  echo "error: VOS_AUTH_TOKEN is required" >&2
  exit 1
fi

if ! command -v cloudflared >/dev/null 2>&1; then
  echo "error: cloudflared is not installed" >&2
  exit 1
fi

if [[ ! -f "${CF_TUNNEL_CONFIG}" ]]; then
  echo "error: tunnel config not found: ${CF_TUNNEL_CONFIG}" >&2
  exit 1
fi

server_pid=""

cleanup() {
  if [[ -n "${server_pid}" ]]; then
    kill "${server_pid}" 2>/dev/null || true
    wait "${server_pid}" 2>/dev/null || true
  fi
}
trap cleanup EXIT INT TERM

echo "[private-stack] starting origin server on ${HOST}:${PORT} (auth required)"
VOS_AUTH_TOKEN="${VOS_AUTH_TOKEN}" \
python3 "${SERVER_SCRIPT}" --host "${HOST}" --port "${PORT}" --no-bonjour --allow-app "${TARGET_APP}" >/tmp/virtualos-origin.log 2>&1 &
server_pid=$!

sleep 2
if ! curl -fsS "http://${HOST}:${PORT}/health" >/dev/null; then
  echo "error: origin server failed health check" >&2
  exit 1
fi

echo "[private-stack] origin healthy; launching cloudflared"
echo "[private-stack] config: ${CF_TUNNEL_CONFIG}"
echo "[private-stack] logs: /tmp/virtualos-origin.log"

exec cloudflared tunnel --config "${CF_TUNNEL_CONFIG}" run
