# Mac Mini Host Setup

This folder packages the Mac mini bootstrap and startup flow into the repo so it does not depend on email snippets or chat history.

## What This Covers

- SSH key install for the host user
- Remote Login enablement
- Xcode CLI tools check
- Optional Homebrew, Cursor, and Tailscale install
- Power settings to keep the machine reachable
- LaunchAgent setup for running `start.sh` at login

## Assumptions

- The Mac mini is signed into a user account that will own the repo, for example `ai`
- The repo is cloned locally on the Mac mini
- `start.sh` exists at the repo root and is the entrypoint for launching `virtualOS`
- The Mac mini will be used as a GUI host, not only a headless SSH box

## Quick Start On The Mac Mini

From the repo root on the Mac mini:

```bash
chmod +x tools/mac_mini/bootstrap.sh
./tools/mac_mini/bootstrap.sh \
  --enable-remote-login \
  --disable-sleep \
  --install-homebrew \
  --install-cursor \
  --install-tailscale
```

If you prefer Finder double-click entrypoints instead of terminal commands:

- `tools/mac_mini/one_click_remote.command`
- `tools/mac_mini/setup_codex_access.command`
- `tools/mac_mini/start_remote_site.command`

If you want to trust a new SSH public key at the same time:

```bash
./tools/mac_mini/bootstrap.sh \
  --ssh-public-key-file /path/to/key.pub \
  --enable-remote-login \
  --disable-sleep
```

## Install Login Startup

If you want `start.sh` to run automatically when the Mac mini user logs in:

```bash
chmod +x tools/mac_mini/install_launch_agent.sh
./tools/mac_mini/install_launch_agent.sh
```

That installer creates:

- `~/Library/LaunchAgents/com.github.yep.virtualos.start.plist`
- `~/Library/Logs/virtualos-startup.log`

The LaunchAgent uses:

- `tools/mac_mini/start_virtualos_at_login.sh`
- `~/.config/virtualos/start.env`

Create the env file before loading the LaunchAgent if `start.sh` needs a VM password:

```bash
mkdir -p ~/.config/virtualos
cat > ~/.config/virtualos/start.env <<'EOF'
VOS_VM_PASSWORD=replace-me
EOF
chmod 600 ~/.config/virtualos/start.env
```

## Manual Checks

After bootstrap:

1. Open Xcode once and let it finish extra component installs.
2. Confirm `Remote Login` is enabled in `System Settings > General > Sharing`.
3. If using Tailscale, sign in from the app and verify the machine appears on your tailnet.
4. Run `./start.sh` once manually before relying on the LaunchAgent.
5. Grant Accessibility and Screen Recording permissions to any app that needs input automation or capture.

## Notes

- `brew install --cask cursor` installs Cursor, but you still need to sign in after install.
- The LaunchAgent runs only for a logged-in Aqua session, which is required for `open` and `osascript`.
- Keep secrets outside the repo. The startup password file lives in `~/.config/virtualos/start.env`.
