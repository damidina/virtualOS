# Cloudflare Private Remote (Zero Trust)

This folder contains a private-only setup for exposing the local `virtualOS` stream server to your iOS/macOS remote clients.

The goal is:
- no public-open endpoint
- Cloudflare Access service-token gate at the edge
- optional origin bearer token gate at your local server

## Architecture

1. Local machine runs:
   - `tools/virtualos_stream_server/server.py`
   - `cloudflared` tunnel to Cloudflare
2. Cloudflare Access protects the hostname.
3. iOS/macOS remote app calls the hostname with:
   - `CF-Access-Client-Id`
   - `CF-Access-Client-Secret`
   - `Authorization: Bearer <origin token>` (optional but recommended)

## 1) Create tunnel and DNS route

```bash
cloudflared tunnel login
cloudflared tunnel create virtualos-remote
cloudflared tunnel route dns virtualos-remote remote.yourdomain.com
```

Save your tunnel UUID and credentials JSON path, then copy `cloudflared-config.example.yml` to a real config file.

## 2) Configure Cloudflare Access (service token only)

In Zero Trust dashboard:
1. Create self-hosted application for `remote.yourdomain.com`.
2. Create a Service Token.
3. Add an Access policy that allows only that Service Token.
4. Add a default deny policy for everyone else.

The remote iOS/macOS apps already support:
- `CF-Access-Client-Id`
- `CF-Access-Client-Secret`

## 3) Run local stack (private mode)

```bash
cd /Users/theone/Documents/GitHub/virtualOS
# optional: cp tools/cloudflare/.env.example .env.private and fill values
VOS_AUTH_TOKEN='replace-with-strong-origin-token' \
CF_TUNNEL_CONFIG='/Users/theone/.cloudflared/virtualos-remote.yml' \
tools/cloudflare/run_private_stack.sh
```

This runs:
- local stream/control server on `127.0.0.1:8899` with auth enforced
- cloudflared tunnel using your config

## 4) Configure remote clients

In both remote apps:
- Connection mode: `Remote`
- Remote URL: `https://remote.yourdomain.com`
- Auth token: same value as `VOS_AUTH_TOKEN`
- CF Access Client ID / Secret: your service token pair

## 5) Verify quickly

```bash
curl -sS \
  -H "CF-Access-Client-Id: $CF_ACCESS_CLIENT_ID" \
  -H "CF-Access-Client-Secret: $CF_ACCESS_CLIENT_SECRET" \
  -H "Authorization: Bearer $VOS_AUTH_TOKEN" \
  "https://remote.yourdomain.com/health"
```

Expected:
- JSON response with `"ok": true`
- `"authRequired": true`

## Security notes

- Do not commit real tunnel credentials or tokens.
- Keep `VOS_AUTH_TOKEN` different from Cloudflare service-token secret.
- If you suspect leakage, rotate both Cloudflare service token and origin token immediately.
