# virtualOS Remote iOS (MVP)

Minimal iOS viewer app for local streaming from your Mac.

## Generate project

```bash
cd /Users/theone/Documents/GitHub/virtualOS/virtualOSRemoteiOS
xcodegen generate
```

## Run in Simulator

```bash
# 1) Start stream server first
cd /Users/theone/Documents/GitHub/virtualOS
python3 tools/virtualos_stream_server/server.py --host 0.0.0.0 --port 8899

# 2) Open iOS project
open /Users/theone/Documents/GitHub/virtualOS/virtualOSRemoteiOS/virtualOSRemoteiOS.xcodeproj
```

In app:
- Connection mode:
  - `Auto`: discovers LAN servers via Bonjour (`_virtualosremote._tcp`)
  - `Direct`: manual `Host` + `Port`
  - `Remote`: full URL (Cloudflare/private reverse proxy)
- Remote-first behavior:
  - If a Remote URL is already saved, app defaults to `Remote`.
  - In `Remote` mode, LAN discovery is disabled.
- `Paste Tunnel` button:
  - Reads clipboard text and auto-extracts a tunnel `https://...` URL.
  - If a 64-char hex token is present, it auto-fills `Auth token (Bearer)`.
- Target app: `Codex` (or `Finder`, `Terminal`, etc.)
- Source: `Window` for focused per-app remote view, `Screen` for full desktop
- Tap `Start`
- Tap on the streamed image to click (normalized dynamic mapping)
- Use shortcut buttons (`Enter`, `Esc`, `Cmd+C`, `Cmd+V`, `Cmd+Tab`)
- Optional auth:
  - `Auth token (Bearer)` for origin auth
  - `CF Access Client ID` + `CF Access Client Secret` for Cloudflare Access

## Run on physical iPhone

1. Connect iPhone + trust computer.
2. In Xcode, choose the `virtualOSRemoteiOS` target and your Team under Signing.
3. Select your iPhone as run destination and press Run.
4. iPhone and Mac must be on same Wi-Fi.
5. In app, set host to your Mac LAN IP (example `192.168.1.23`) and port `8899`.
6. Tap `Start`.

## Private Cloudflare mode

If you want no public-open endpoint:

1. Set connection mode to `Remote`.
2. Set remote URL to your protected hostname (example `https://remote.yourdomain.com`).
3. Fill `Auth token (Bearer)`.
4. Fill `CF Access Client ID` + `CF Access Client Secret`.

Setup reference:
- `/Users/theone/Documents/GitHub/virtualOS/tools/cloudflare/README.md`

To find Mac IP:

```bash
ipconfig getifaddr en0
```
