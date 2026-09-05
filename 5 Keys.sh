#!/usr/bin/env bash

set -euo pipefail

# Installs the SSH key from 1Password on macOS and Omarchy/Arch.
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib/report.sh
. "$SCRIPT_DIR/lib/report.sh"

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
    local add_command
    printf -v add_command '%q ' "${SSH_ADD_CMD[@]}" "$key_path"
    report_action ssh-passphrase 'SSH key → enter passphrase' "Run (Bash): $add_command"
    report_deferred
    return
  fi

  ensure_ssh_agent_running
  "${SSH_ADD_CMD[@]}" "$key_path"
}

SSH_ADD_CMD=(ssh-add)

if ! command -v op >/dev/null 2>&1; then
  printf '1Password CLI (op) is not installed; skipping SSH key setup.\n' >&2
  report_action ssh-keys '1Password → install CLI' \
    'Install 1Password CLI: https://developer.1password.com/docs/cli/get-started/' \
    "Then rerun (Bash): $(printf 'bash %q' "$SCRIPT_DIR/5 Keys.sh")"
  report_deferred
  exit 0
fi

if ! op whoami >/dev/null 2>&1; then
  printf '1Password CLI is not signed in; skipping SSH key setup to keep this script unattended.\n' >&2
  report_keys_action
  report_deferred
  exit 0
fi

# A login may have completed since the software stage recorded its reminder.
if [ -n "${BOOTSTRAP_REPORT_DIR:-}" ]; then
  rm -f "$BOOTSTRAP_REPORT_DIR/actions/ssh-keys"
fi

if [ "$(uname -s)" = "Darwin" ]; then
  ensure_macos_ssh_agent
  SSH_ADD_CMD=(ssh-add --apple-use-keychain)
else
  sudo pacman -S --needed --noconfirm openssh
fi

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
