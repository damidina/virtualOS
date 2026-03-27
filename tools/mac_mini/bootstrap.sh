#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: bootstrap.sh [options]

Options:
  --ssh-public-key-file PATH   Append a public key file to ~/.ssh/authorized_keys
  --ssh-public-key KEY         Append a literal public key to ~/.ssh/authorized_keys
  --enable-remote-login        Enable macOS Remote Login with systemsetup
  --disable-sleep              Disable sleep and enable Wake-on-LAN
  --install-homebrew           Install Homebrew if missing
  --install-cursor             Install Cursor with Homebrew
  --install-tailscale          Install Tailscale with Homebrew
  --help                       Show this help
EOF
}

SSH_PUBLIC_KEY_FILE=""
SSH_PUBLIC_KEY=""
ENABLE_REMOTE_LOGIN=0
DISABLE_SLEEP=0
INSTALL_HOMEBREW=0
INSTALL_CURSOR=0
INSTALL_TAILSCALE=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --ssh-public-key-file)
      SSH_PUBLIC_KEY_FILE="${2:-}"
      shift 2
      ;;
    --ssh-public-key)
      SSH_PUBLIC_KEY="${2:-}"
      shift 2
      ;;
    --enable-remote-login)
      ENABLE_REMOTE_LOGIN=1
      shift
      ;;
    --disable-sleep)
      DISABLE_SLEEP=1
      shift
      ;;
    --install-homebrew)
      INSTALL_HOMEBREW=1
      shift
      ;;
    --install-cursor)
      INSTALL_CURSOR=1
      shift
      ;;
    --install-tailscale)
      INSTALL_TAILSCALE=1
      shift
      ;;
    --help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [[ -n "$SSH_PUBLIC_KEY_FILE" && -n "$SSH_PUBLIC_KEY" ]]; then
  echo "Use either --ssh-public-key-file or --ssh-public-key, not both." >&2
  exit 1
fi

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "This script is intended for macOS hosts." >&2
  exit 1
fi

append_public_key() {
  local key_text="$1"

  mkdir -p "$HOME/.ssh"
  chmod 700 "$HOME/.ssh"
  touch "$HOME/.ssh/authorized_keys"
  chmod 600 "$HOME/.ssh/authorized_keys"

  if grep -Fqx "$key_text" "$HOME/.ssh/authorized_keys"; then
    echo "SSH public key already present."
    return
  fi

  printf '%s\n' "$key_text" >> "$HOME/.ssh/authorized_keys"
  echo "Added SSH public key to $HOME/.ssh/authorized_keys"
}

ensure_xcode_cli_tools() {
  if xcode-select -p >/dev/null 2>&1; then
    echo "Xcode Command Line Tools already present."
    return
  fi

  echo "Requesting Xcode Command Line Tools install..."
  xcode-select --install || true
}

ensure_homebrew() {
  if command -v brew >/dev/null 2>&1; then
    echo "Homebrew already present."
    return
  fi

  echo "Installing Homebrew..."
  NONINTERACTIVE=1 /bin/bash -c \
    "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
}

load_brew_shellenv() {
  if [[ -x /opt/homebrew/bin/brew ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
    return
  fi

  if [[ -x /usr/local/bin/brew ]]; then
    eval "$(/usr/local/bin/brew shellenv)"
  fi
}

install_cask() {
  local cask_name="$1"

  if brew list --cask "$cask_name" >/dev/null 2>&1; then
    echo "$cask_name already installed."
    return
  fi

  echo "Installing $cask_name..."
  brew install --cask "$cask_name"
}

if [[ -n "$SSH_PUBLIC_KEY_FILE" ]]; then
  if [[ ! -f "$SSH_PUBLIC_KEY_FILE" ]]; then
    echo "Public key file not found: $SSH_PUBLIC_KEY_FILE" >&2
    exit 1
  fi
  append_public_key "$(tr -d '\r' < "$SSH_PUBLIC_KEY_FILE")"
fi

if [[ -n "$SSH_PUBLIC_KEY" ]]; then
  append_public_key "$SSH_PUBLIC_KEY"
fi

ensure_xcode_cli_tools

if (( ENABLE_REMOTE_LOGIN )); then
  echo "Enabling Remote Login..."
  sudo systemsetup -setremotelogin on
fi

if (( DISABLE_SLEEP )); then
  echo "Updating power settings..."
  sudo pmset -a sleep 0 disksleep 0 displaysleep 30
  sudo pmset -a womp 1
fi

if (( INSTALL_HOMEBREW || INSTALL_CURSOR || INSTALL_TAILSCALE )); then
  ensure_homebrew
  load_brew_shellenv
fi

if (( INSTALL_CURSOR )); then
  install_cask cursor
fi

if (( INSTALL_TAILSCALE )); then
  install_cask tailscale
fi

echo
echo "Bootstrap complete."
echo "Next steps:"
echo "  1. Open Xcode once and let it finish any extra installs."
echo "  2. Verify Remote Login access for this user in System Settings."
echo "  3. Run ./start.sh manually once before installing the LaunchAgent."
