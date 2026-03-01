# virtualOS Remote macOS (MVP)

Minimal macOS companion app that connects to the same local stream/control server as the iOS app.

## Generate project

```bash
cd /Users/theone/Documents/GitHub/virtualOS/virtualOSRemoteMac
xcodegen generate
```

## Run

```bash
# 1) Start server
cd /Users/theone/Documents/GitHub/virtualOS
python3 tools/virtualos_stream_server/server.py --host 0.0.0.0 --port 8899

# 2) Open mac app project
open /Users/theone/Documents/GitHub/virtualOS/virtualOSRemoteMac/virtualOSRemoteMac.xcodeproj
```

In app:
- Connection mode:
  - `Auto`: discovers LAN servers via Bonjour (`_virtualosremote._tcp`) and auto-selects non-local host first
  - `Direct`: manual `Host` + `Port`
  - `Remote`: full URL (for Cloudflare Tunnel / HTTPS reverse proxy), e.g. `https://vm-control.example.com`
- Optional auth:
  - `Auth token (Bearer)` for origin auth
  - `CF Access Client ID` + `CF Access Client Secret` for Cloudflare Access
- Target app: `Codex` (or `virtualOS`, `Finder`, etc.)
- Source:
  - `Window` for per-app window capture
  - `Screen` for display capture (auto-picks display nearest/overlapping target app)
- `Servers` menu shows discovered hosts and allows one-click selection.
- Shortcut row is app-aware (Codex/Finder/Chrome/Terminal presets).

Private Cloudflare setup:
- `/Users/theone/Documents/GitHub/virtualOS/tools/cloudflare/README.md`
