#!/usr/bin/env sh
set -eu

# Bootstrap this laptop config repo from either:
#   1. an existing clone: ./bootstrap.sh
#   2. a URL pipe: curl -fsSL <raw bootstrap.sh url> | sh
#
# Useful overrides:
#   CONFIG_ARCHIVE_URL=https://github.com/SomeoneWithOptions/config/archive/refs/heads/main.tar.gz
#   CONFIG_REF=main
#   CONFIG_DIR=/path/to/existing/clone
#   BOOTSTRAP_SUDO=0        # do not pre-authenticate/keep sudo warm
#   BOOTSTRAP_KEYS=0        # skip 1Password/SSH key step

REPO_OWNER="${REPO_OWNER:-SomeoneWithOptions}"
REPO_NAME="${REPO_NAME:-config}"
CONFIG_REF="${CONFIG_REF:-main}"
CONFIG_ARCHIVE_URL="${CONFIG_ARCHIVE_URL:-https://github.com/${REPO_OWNER}/${REPO_NAME}/archive/refs/heads/${CONFIG_REF}.tar.gz}"
BOOTSTRAP_SUDO="${BOOTSTRAP_SUDO:-1}"
BOOTSTRAP_KEYS="${BOOTSTRAP_KEYS:-1}"

log() {
  printf '[bootstrap] %s\n' "$*"
}

have() {
  command -v "$1" >/dev/null 2>&1
}

script_dir() {
  # Works when executed as a file. When piped to sh, $0 is usually sh and this
  # intentionally falls back to download mode unless CONFIG_DIR is supplied.
  case "$0" in
    */*)
      cd "$(dirname "$0")" 2>/dev/null && pwd
      ;;
    *)
      pwd
      ;;
  esac
}

is_config_repo() {
  [ -f "$1/1 SoftwareInstall.sh" ] && \
  [ -f "$1/2 Fonts.sh" ] && \
  [ -f "$1/3 Git.sh" ] && \
  [ -f "$1/4 ConfigFiles.sh" ] && \
  [ -f "$1/5 Keys.sh" ]
}

prepare_config_dir() {
  if [ -n "${CONFIG_DIR:-}" ]; then
    if is_config_repo "$CONFIG_DIR"; then
      printf '%s\n' "$CONFIG_DIR"
      return 0
    fi
    log "CONFIG_DIR is not this config repo: $CONFIG_DIR" >&2
    return 1
  fi

  local_dir="$(script_dir)"
  if is_config_repo "$local_dir"; then
    printf '%s\n' "$local_dir"
    return 0
  fi

  pwd_dir="$(pwd)"
  if is_config_repo "$pwd_dir"; then
    printf '%s\n' "$pwd_dir"
    return 0
  fi

  if ! have curl; then
    log "curl is required to download the repo archive." >&2
    return 1
  fi
  if ! have tar; then
    log "tar is required to unpack the repo archive." >&2
    return 1
  fi

  tmp_dir="$(mktemp -d 2>/dev/null || mktemp -d -t config-bootstrap)"
  archive="$tmp_dir/config.tar.gz"

  log "Downloading config repo: $CONFIG_ARCHIVE_URL"
  curl -fsSL "$CONFIG_ARCHIVE_URL" -o "$archive"

  log "Extracting config repo to: $tmp_dir"
  tar -xzf "$archive" -C "$tmp_dir"

  extracted_dir=""
  for candidate in "$tmp_dir"/*; do
    if [ -d "$candidate" ]; then
      extracted_dir="$candidate"
      break
    fi
  done

  if [ -z "$extracted_dir" ] || ! is_config_repo "$extracted_dir"; then
    log "Downloaded archive did not contain the expected config repo files." >&2
    return 1
  fi

  printf '%s\n' "$extracted_dir"
}

start_sudo_keepalive() {
  if [ "$BOOTSTRAP_SUDO" != "1" ] || ! have sudo; then
    return 0
  fi

  log "Refreshing sudo credentials once. You may be prompted for your password."
  sudo -v

  # Keep sudo timestamp fresh while bootstrap runs, avoiding repeated prompts.
  (
    while true; do
      sudo -n true 2>/dev/null || exit
      sleep 60
    done
  ) &
  SUDO_KEEPALIVE_PID="$!"
  trap 'if [ -n "${SUDO_KEEPALIVE_PID:-}" ]; then kill "$SUDO_KEEPALIVE_PID" 2>/dev/null || true; fi' EXIT INT TERM
}

run_script() {
  label="$1"
  path="$2"

  if [ ! -f "$path" ]; then
    log "Missing script: $path" >&2
    return 1
  fi

  log "Running: $label"
  /usr/bin/env bash "$path"
}

main() {
  CONFIG_ROOT="$(prepare_config_dir)"
  log "Using config repo at: $CONFIG_ROOT"

  start_sudo_keepalive

  export DEBIAN_FRONTEND="${DEBIAN_FRONTEND:-noninteractive}"
  export HOMEBREW_NO_ANALYTICS="${HOMEBREW_NO_ANALYTICS:-1}"
  export HOMEBREW_NO_ENV_HINTS="${HOMEBREW_NO_ENV_HINTS:-1}"
  export NONINTERACTIVE="${NONINTERACTIVE:-1}"

  run_script "software install" "$CONFIG_ROOT/1 SoftwareInstall.sh"
  run_script "fonts" "$CONFIG_ROOT/2 Fonts.sh"
  run_script "git config" "$CONFIG_ROOT/3 Git.sh"
  run_script "config files" "$CONFIG_ROOT/4 ConfigFiles.sh"

  if [ "$BOOTSTRAP_KEYS" = "1" ]; then
    # This script is intentionally safe to run unattended: it exits 0 when op is
    # missing or not signed in, and can be rerun after signing into 1Password.
    run_script "1Password SSH keys" "$CONFIG_ROOT/5 Keys.sh" || true
  else
    log "Skipping 1Password SSH key step because BOOTSTRAP_KEYS=0."
  fi

  log "Done. If 1Password was not signed in, sign in and rerun: bash '$CONFIG_ROOT/5 Keys.sh'"
}

main "$@"
