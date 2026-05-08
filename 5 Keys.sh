#!/bin/bash

set -euo pipefail

# Detect the current platform using available tools (sw_vers, /etc/os-release, uname).
detect_platform() {
  if command -v sw_vers >/dev/null 2>&1; then
    printf 'macos'
    return
  fi

  if [ -r /etc/os-release ]; then
    . /etc/os-release
    case "${ID:-}" in
      arch)
        printf 'arch'
        return
        ;;
    esac
  fi

  case "$(uname -s 2>/dev/null || true)" in
    Darwin)
      printf 'macos'
      ;;
    Linux)
      printf 'linux'
      ;;
    *)
      printf 'unknown'
      ;;
  esac
}

# Ensure an ssh-agent is available. Reuse existing agent when possible.
agent_is_reachable() {
  local status

  if [ -z "${SSH_AUTH_SOCK:-}" ]; then
    return 1
  fi

  if ssh-add -l >/dev/null 2>&1; then
    return 0
  fi

  status=$?
  # ssh-add exits 1 when agent is reachable but empty.
  [ "$status" -eq 1 ]
}

ensure_ssh_agent_running() {
  local agent_env_path="$HOME/.ssh/agent.env"

  mkdir -p "$HOME/.ssh"
  chmod 700 "$HOME/.ssh"

  if agent_is_reachable; then
    return
  fi

  if [ -r "$agent_env_path" ]; then
    # shellcheck disable=SC1090
    . "$agent_env_path"
    if agent_is_reachable; then
      return
    fi
  fi

  eval "$(ssh-agent -s)" >/dev/null
  umask 077
  printf 'SSH_AUTH_SOCK=%q; export SSH_AUTH_SOCK\nSSH_AGENT_PID=%q; export SSH_AGENT_PID\n' \
    "$SSH_AUTH_SOCK" "$SSH_AGENT_PID" >"$agent_env_path"
}

# On macOS, load the system ssh-agent LaunchAgent if necessary.
ensure_macos_ssh_agent() {
  if command -v launchctl >/dev/null 2>&1; then
    if ! launchctl list | grep -q com.openssh.ssh-agent; then
      launchctl load -w /System/Library/LaunchAgents/com.openssh.ssh-agent.plist 2>/dev/null || true
    fi
  fi
}

write_op_secret_if_changed() {
  local op_path="$1"
  local dest_path="$2"
  local mode="$3"
  local tmp_path

  tmp_path="$(mktemp)"
  trap 'rm -f "$tmp_path"; trap - RETURN' RETURN

  op read "$op_path" >"$tmp_path"

  if [ ! -f "$dest_path" ] || ! cmp -s "$tmp_path" "$dest_path"; then
    install -m "$mode" "$tmp_path" "$dest_path"
    printf 'Updated %s\n' "$dest_path"
  else
    chmod "$mode" "$dest_path"
  fi
}

ssh_key_loaded() {
  local fingerprint="$1"

  ensure_ssh_agent_running
  ssh-add -l 2>/dev/null | grep -Fq "$fingerprint"
}

add_ssh_key_if_missing() {
  local key_path="$1"
  local fingerprint="$2"

  if ssh_key_loaded "$fingerprint"; then
    printf 'SSH key already loaded: %s\n' "$fingerprint"
    return
  fi

  if ! ssh-keygen -y -P "" -f "$key_path" >/dev/null 2>&1; then
    printf 'SSH key %s appears to require a passphrase; skipping ssh-add to keep this script unattended.\n' "$key_path" >&2
    printf 'Add it manually later with: ssh-add %s\n' "$key_path" >&2
    return
  fi

  ensure_ssh_agent_running
  "${SSH_ADD_CMD[@]}" "$key_path"
}

PLATFORM="$(detect_platform)"
SSH_ADD_CMD=(ssh-add)

if ! command -v op >/dev/null 2>&1; then
  printf '1Password CLI (op) is not installed; skipping SSH key setup.\n' >&2
  exit 0
fi

if ! op whoami >/dev/null 2>&1; then
  printf '1Password CLI is not signed in; skipping SSH key setup to keep this script unattended.\n' >&2
  printf 'Sign in with "op account add" or "op signin", then rerun this script.\n' >&2
  exit 0
fi

case "$PLATFORM" in
  arch)
    if command -v sudo >/dev/null 2>&1; then
      sudo pacman -S --needed --noconfirm openssh
    else
      pacman -S --needed --noconfirm openssh
    fi
    ;;
  macos)
    ensure_macos_ssh_agent
    SSH_ADD_CMD=(ssh-add --apple-use-keychain)
    ;;
  *)
    ensure_ssh_agent_running
    ;;
esac

mkdir -p "$HOME/.ssh"
chmod 700 "$HOME/.ssh"

SSH_PRIVATE_DEST="${SSH_PRIVATE_DEST:-$HOME/.ssh/id_rsa}"
SSH_PUBLIC_DEST="${SSH_PUBLIC_DEST:-$HOME/.ssh/id_rsa.pub}"
OP_SSH_PRIVATE_REF="${OP_SSH_PRIVATE_REF:-op://Private/id_rsa/private key}"
OP_SSH_PUBLIC_REF="${OP_SSH_PUBLIC_REF:-op://Private/id_rsa/public key}"
OP_SSH_FINGERPRINT_REF="${OP_SSH_FINGERPRINT_REF:-op://Private/id_rsa/fingerprint}"
OP_SSH_TYPE_REF="${OP_SSH_TYPE_REF:-op://Private/id_rsa/key type}"

write_op_secret_if_changed "$OP_SSH_PRIVATE_REF" "$SSH_PRIVATE_DEST" 600
write_op_secret_if_changed "$OP_SSH_PUBLIC_REF" "$SSH_PUBLIC_DEST" 644

FINGERPRINT="$(op read "$OP_SSH_FINGERPRINT_REF")"
KEY_TYPE="$(op read "$OP_SSH_TYPE_REF")"

printf 'Loaded %s key with fingerprint %s\n' "$KEY_TYPE" "$FINGERPRINT"

add_ssh_key_if_missing "$SSH_PRIVATE_DEST" "$FINGERPRINT"
