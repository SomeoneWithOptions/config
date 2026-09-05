#!/usr/bin/env sh
set -eu

# Download a fresh archive, then run the numbered scripts on macOS or Omarchy.
# Overrides:
#   CONFIG_ARCHIVE_URL=... CONFIG_REF=main
#   BOOTSTRAP_ALLOW_CONFIG_DIR=1 CONFIG_DIR=/path/to/clone
#   BOOTSTRAP_SUDO=0       skip sudo pre-authentication/keepalive
#   BOOTSTRAP_KEYS=0       deliberately skip SSH key setup
#   BOOTSTRAP_VERBOSE=1    also stream installer output
#   NO_COLOR=1            disable terminal colors

REPO_OWNER="${REPO_OWNER:-SomeoneWithOptions}"
REPO_NAME="${REPO_NAME:-config}"
CONFIG_REF="${CONFIG_REF:-main}"
CONFIG_ARCHIVE_URL="${CONFIG_ARCHIVE_URL:-https://github.com/${REPO_OWNER}/${REPO_NAME}/archive/refs/heads/${CONFIG_REF}.tar.gz}"
BOOTSTRAP_SUDO="${BOOTSTRAP_SUDO:-1}"
BOOTSTRAP_KEYS="${BOOTSTRAP_KEYS:-1}"
BOOTSTRAP_VERBOSE="${BOOTSTRAP_VERBOSE:-0}"
CURRENT_STAGE=preparation
SUDO_KEEPALIVE_PID=''
HEARTBEAT_PID=''
FOLLOW_PID=''
RESTORE_IDLE=0

have() { command -v "$1" >/dev/null 2>&1; }

# Keep bootstrap self-contained: the shared helper is not available until after
# the archive download. Use /tmp explicitly on both supported platforms.
exec 3>&2
RUN_DIR=$(mktemp -d /tmp/config-bootstrap.XXXXXX)
chmod 700 "$RUN_DIR"
LOG_FILE="$RUN_DIR/install.log"
BOOTSTRAP_REPORT_DIR="$RUN_DIR/report"
export BOOTSTRAP_REPORT_DIR BOOTSTRAP_KEYS
(
  umask 077
  mkdir -p "$BOOTSTRAP_REPORT_DIR/actions" "$BOOTSTRAP_REPORT_DIR/stages"
  : >"$BOOTSTRAP_REPORT_DIR/warnings"
  : >"$LOG_FILE"
)
GREEN='' YELLOW='' RED='' RESET=''
if [ -t 3 ] && [ "${TERM:-dumb}" != dumb ] && [ -z "${NO_COLOR+x}" ]; then
  GREEN=$(printf '\033[32m') YELLOW=$(printf '\033[33m')
  RED=$(printf '\033[31m') RESET=$(printf '\033[0m')
fi
ui() { printf '%s\n' "$*" >&3; }
log() { printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"; }

stop_background() {
  for background_pid in "$HEARTBEAT_PID" "$SUDO_KEEPALIVE_PID" "$FOLLOW_PID"; do
    if [ -n "$background_pid" ]; then
      kill "$background_pid" 2>/dev/null || true
      wait "$background_pid" 2>/dev/null || true
    fi
  done
}

render_summary() {
  printf '\n'
  if [ "$FINAL_STATUS" -ne 0 ]; then
    printf 'Setup stopped — %s (exit %s).\n' "$CURRENT_STAGE" "$FINAL_STATUS"
  elif [ -s "$BOOTSTRAP_REPORT_DIR/warnings" ]; then
    printf 'Setup finished with warnings.\n'
  else
    printf 'Setup finished.\n'
  fi
  printf 'Detailed log: %s\n' "$LOG_FILE"
  printf 'Saved summary: %s/summary.txt\n' "$RUN_DIR"
  if [ -s "$BOOTSTRAP_REPORT_DIR/warnings" ]; then
    printf '\nWARNINGS\n'
    while IFS= read -r warning; do printf '  ! %s\n' "$warning"; done <"$BOOTSTRAP_REPORT_DIR/warnings"
  fi
  action_count=0
  for action_file in "$BOOTSTRAP_REPORT_DIR/actions/"*; do
    [ -f "$action_file" ] || continue
    action_count=$((action_count + 1))
  done
  if [ "$action_count" -gt 0 ]; then
    printf '\nACTION NEEDED · %s\n' "$action_count"
    action_number=0
    for action_file in "$BOOTSTRAP_REPORT_DIR/actions/"*; do
      [ -f "$action_file" ] || continue
      action_number=$((action_number + 1))
      {
        IFS= read -r action_title
        printf '\n%s. %s\n' "$action_number" "$action_title"
        while IFS= read -r action_line; do printf '   %s\n' "$action_line"; done
      } <"$action_file"
    done
  fi
}

finish() {
  FINAL_STATUS=$?
  trap - EXIT INT TERM
  # tail polls once per second. Let it drain normal completion before stopping.
  if [ -n "$FOLLOW_PID" ]; then sleep 1; fi
  stop_background
  if [ "$RESTORE_IDLE" = 1 ]; then
    if ! omarchy toggle idle allow-idle; then
      printf '%s\n' 'setup: Could not restore idle behavior. Run: omarchy toggle idle allow-idle' >>"$BOOTSTRAP_REPORT_DIR/warnings"
    fi
  fi
  (umask 077; render_summary >"$RUN_DIR/summary.txt")
  cat "$RUN_DIR/summary.txt" >&3
  cat "$RUN_DIR/summary.txt" >>"$LOG_FILE"
  exit "$FINAL_STATUS"
}
trap finish EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
exec >>"$LOG_FILE" 2>&1
ui 'Config setup'
ui "Detailed log: $LOG_FILE"
ui ''
if [ "$BOOTSTRAP_VERBOSE" = 1 ]; then
  tail -n +1 -f "$LOG_FILE" >&3 &
  FOLLOW_PID=$!
fi

is_config_repo() {
  [ -f "$1/1 SoftwareInstall.sh" ] && [ -f "$1/2 Fonts.sh" ] && \
  [ -f "$1/3 Git.sh" ] && [ -f "$1/4 ConfigFiles.sh" ] && \
  [ -f "$1/5 Keys.sh" ] && [ -f "$1/lib/report.sh" ]
}

prepare_config_dir() {
  if [ "${BOOTSTRAP_ALLOW_CONFIG_DIR:-0}" = 1 ] && [ -n "${CONFIG_DIR:-}" ]; then
    if ! is_config_repo "$CONFIG_DIR"; then
      log "CONFIG_DIR is not this config repo: $CONFIG_DIR"
      return 1
    fi
    CONFIG_ROOT=$(cd "$CONFIG_DIR" && pwd)
    return
  fi
  have curl || { log 'curl is required to download the repo archive.'; return 1; }
  have tar || { log 'tar is required to unpack the repo archive.'; return 1; }
  ui '→ Downloading config repository'
  # Do not log the URL: an override may contain credentials or signed parameters.
  curl -fsSL "$CONFIG_ARCHIVE_URL" -o "$RUN_DIR/config.tar.gz"
  mkdir "$RUN_DIR/source"
  tar -xzf "$RUN_DIR/config.tar.gz" -C "$RUN_DIR/source"
  CONFIG_ROOT=''
  for candidate in "$RUN_DIR/source/"*; do
    if [ -d "$candidate" ] && is_config_repo "$candidate"; then
      CONFIG_ROOT=$candidate
      break
    fi
  done
  [ -n "$CONFIG_ROOT" ] || { log 'Archive is missing expected config repo files.'; return 1; }
}

keep_omarchy_awake() {
  [ "$(uname -s)" = Linux ] && have omarchy || return 0
  CURRENT_STAGE='idle prevention'
  ui '→ Keeping Omarchy awake during installation'
  # Explicit stay-awake is idempotent; a bare toggle could enable idle instead.
  # Preserve a pre-existing user preference and otherwise restore it on exit.
  if [ ! -f "$HOME/.local/state/omarchy/indicators/stay-awake" ]; then
    RESTORE_IDLE=1
  fi
  omarchy toggle idle stay-awake
}

start_sudo_keepalive() {
  [ "$BOOTSTRAP_SUDO" = 1 ] && have sudo || return 0
  ui '→ Sudo authentication (password prompt may appear)'
  # Bootstrap is commonly piped into sh; never consume that pipe for input.
  if [ -t 3 ] && [ -r /dev/tty ]; then
    sudo -v </dev/tty >&3 2>&3
  else
    sudo -n -v
  fi
  (
    while true; do
      sudo -n true 2>/dev/null || exit
      sleep 60
    done
  ) &
  SUDO_KEEPALIVE_PID=$!
}

run_script() {
  label=$1
  path=$2
  BOOTSTRAP_STAGE=$3
  export BOOTSTRAP_STAGE
  CURRENT_STAGE=$label
  [ -f "$path" ] || { log "Missing script: $path"; return 1; }
  stage_start=$(date +%s)
  ui "→ $label"
  log "START $label"
  # Keep long package builds visibly alive, without per-package console noise.
  (
    heartbeat_seconds=0
    while sleep 1; do
      heartbeat_seconds=$((heartbeat_seconds + 1))
      if [ "$heartbeat_seconds" -ge 30 ]; then
        ui "  … $label still running ($(( $(date +%s) - stage_start ))s)"
        heartbeat_seconds=0
      fi
    done
  ) &
  HEARTBEAT_PID=$!
  # Keep installers in the foreground: background jobs inherit ignored SIGINT,
  # which would make Ctrl-C leave package managers running behind the summary.
  stage_status=0
  if have systemd-inhibit; then
    systemd-inhibit --what=idle:sleep --who=config-bootstrap --why="Running $label" \
      /usr/bin/env bash "$path" </dev/null || stage_status=$?
  else
    /usr/bin/env bash "$path" </dev/null || stage_status=$?
  fi
  kill "$HEARTBEAT_PID" 2>/dev/null || true
  wait "$HEARTBEAT_PID" 2>/dev/null || true
  HEARTBEAT_PID=''
  elapsed=$(( $(date +%s) - stage_start ))
  log "END $label: exit=$stage_status elapsed=${elapsed}s"
  if [ "$stage_status" -ne 0 ]; then
    ui "${RED}✗ $label — failed (exit $stage_status)${RESET} · ${elapsed}s"
  elif [ -f "$BOOTSTRAP_REPORT_DIR/stages/$BOOTSTRAP_STAGE.warning" ]; then
    ui "${YELLOW}! $label — completed with warnings${RESET} · ${elapsed}s"
  elif [ -f "$BOOTSTRAP_REPORT_DIR/stages/$BOOTSTRAP_STAGE.deferred" ]; then
    ui "${YELLOW}! $label — deferred; action needed${RESET} · ${elapsed}s"
  elif [ -f "$BOOTSTRAP_REPORT_DIR/stages/$BOOTSTRAP_STAGE.action" ]; then
    ui "${YELLOW}! $label — completed; action needed${RESET} · ${elapsed}s"
  else
    ui "${GREEN}✓ $label${RESET} · ${elapsed}s"
  fi
  return "$stage_status"
}

main() {
  prepare_config_dir
  log "Using config repo at: $CONFIG_ROOT"
  CURRENT_STAGE='sudo authentication'
  start_sudo_keepalive
  keep_omarchy_awake
  export HOMEBREW_NO_ANALYTICS="${HOMEBREW_NO_ANALYTICS:-1}"
  export HOMEBREW_NO_ENV_HINTS="${HOMEBREW_NO_ENV_HINTS:-1}"
  export NONINTERACTIVE="${NONINTERACTIVE:-1}"
  run_script 'Software' "$CONFIG_ROOT/1 SoftwareInstall.sh" software
  run_script 'Fonts' "$CONFIG_ROOT/2 Fonts.sh" fonts
  run_script 'Git' "$CONFIG_ROOT/3 Git.sh" git
  run_script 'Config files' "$CONFIG_ROOT/4 ConfigFiles.sh" config
  if [ "$BOOTSTRAP_KEYS" = 1 ]; then
    run_script 'SSH keys' "$CONFIG_ROOT/5 Keys.sh" keys
  else
    ui '– SSH keys skipped (BOOTSTRAP_KEYS=0)'
  fi
}

main "$@"
