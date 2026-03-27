# virtualOS

Run a virtual macOS machine on your Apple Silicon computer.

On first start, the latest macOS restore image can be downloaded from Apple servers. After installation has finished, you can start using the virtual machine by performing the initial operating system (OS) setup.

You can configure the following virtual machine parameters:
- CPU count
- RAM
- Screen size
- Shared folder

To use USB disks, you can set the location where VM files are stored.

Unlike other apps on the AppStore, no In-App purchases are required for managing multiple virtual machines, setting CPU count or the amount of RAM.

## Download

You can download this app from the [macOS AppStore](https://apps.apple.com/us/app/virtualos/id1614659226)

This application is free and open source software, source code is available at: https://github.com/yep/virtualOS

Mac and macOS are trademarks of Apple Inc., registered in the U.S. and other countries and regions.

## Mac Mini Host Setup

If you want to use a Mac mini as the always-on `virtualOS` host, see:

- `tools/mac_mini/README.md`

Quick start on the Mac mini from the repo root:

```bash
chmod +x tools/mac_mini/bootstrap.sh tools/mac_mini/install_launch_agent.sh
./tools/mac_mini/bootstrap.sh \
  --enable-remote-login \
  --disable-sleep \
  --install-homebrew \
  --install-cursor \
  --install-tailscale
./tools/mac_mini/install_launch_agent.sh
```

If `start.sh` needs a VM password for unattended login startup, create:

```bash
mkdir -p ~/.config/virtualos
cat > ~/.config/virtualos/start.env <<'EOF'
VOS_VM_PASSWORD=replace-me
EOF
chmod 600 ~/.config/virtualos/start.env
```

If you prefer Finder double-click instead of Terminal:

- `tools/mac_mini/one_click_remote.command`
- `tools/mac_mini/setup_codex_access.command`
- `tools/mac_mini/start_remote_site.command`
