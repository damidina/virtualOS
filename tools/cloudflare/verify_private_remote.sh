#!/usr/bin/env bash
set -euo pipefail

if [[ -z "${REMOTE_URL:-}" ]]; then
  echo "error: set REMOTE_URL (example: https://remote.yourdomain.com)" >&2
  exit 1
fi

if [[ -z "${CF_ACCESS_CLIENT_ID:-}" ]] || [[ -z "${CF_ACCESS_CLIENT_SECRET:-}" ]]; then
  echo "error: set CF_ACCESS_CLIENT_ID and CF_ACCESS_CLIENT_SECRET" >&2
  exit 1
fi

if [[ -z "${VOS_AUTH_TOKEN:-}" ]]; then
  echo "error: set VOS_AUTH_TOKEN" >&2
  exit 1
fi

echo "[verify] GET ${REMOTE_URL}/health"
curl -fsS \
  -H "CF-Access-Client-Id: ${CF_ACCESS_CLIENT_ID}" \
  -H "CF-Access-Client-Secret: ${CF_ACCESS_CLIENT_SECRET}" \
  -H "Authorization: Bearer ${VOS_AUTH_TOKEN}" \
  "${REMOTE_URL%/}/health"
echo

echo "[verify] GET ${REMOTE_URL}/frame.jpg (window Codex)"
tmp="${TMPDIR:-/tmp}/virtualos-remote-verify.jpg"
code="$(curl -sS -o "${tmp}" -w '%{http_code}' \
  -H "CF-Access-Client-Id: ${CF_ACCESS_CLIENT_ID}" \
  -H "CF-Access-Client-Secret: ${CF_ACCESS_CLIENT_SECRET}" \
  -H "Authorization: Bearer ${VOS_AUTH_TOKEN}" \
  "${REMOTE_URL%/}/frame.jpg?source=window&app=Codex&max=1400")"
size="$(wc -c <"${tmp}" 2>/dev/null || echo 0)"
echo "http=${code} size=${size} file=${tmp}"

if [[ "${code}" != "200" ]] || [[ "${size}" -lt 10000 ]]; then
  echo "verify failed" >&2
  exit 1
fi

echo "verify ok"
