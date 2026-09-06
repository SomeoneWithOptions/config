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
SOFTWARE_EVENTS_FILE="$RUN_DIR/software-progress"
SOFTWARE_EVENTS_STOP="$RUN_DIR/software-renderer.stop"
SOFTWARE_RENDERER_PID=''
BOOTSTRAP_REPORT_DIR="$RUN_DIR/report"
export BOOTSTRAP_REPORT_DIR BOOTSTRAP_KEYS
(
  umask 077
  mkdir -p "$BOOTSTRAP_REPORT_DIR/actions" "$BOOTSTRAP_REPORT_DIR/stages"
  : >"$BOOTSTRAP_REPORT_DIR/warnings"
  : >"$LOG_FILE"
  : >"$SOFTWARE_EVENTS_FILE"
)
GREEN='' YELLOW='' RED='' RESET=''
if [ -t 3 ] && [ "${TERM:-dumb}" != dumb ] && [ -z "${NO_COLOR+x}" ]; then
  GREEN=$(printf '\033[32m') YELLOW=$(printf '\033[33m')
  RED=$(printf '\033[31m') RESET=$(printf '\033[0m')
fi
ui() { printf '%s\n' "$*" >&3; }
log() { printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"; }

# Renders app-by-app software progress from the private TSV events file that
# report_software_progress appends to. Polls at most once per second, keeps one
# active line for the current operation (rewritten on capable terminals, plain
# newlines otherwise), heartbeats the current operation's elapsed time, and
# drains remaining events after the stop file appears before exiting. Silent
# when BOOTSTRAP_VERBOSE=1: the streamed transcript already carries the same
# readable records, so dedicated rows would only duplicate them.
software_renderer() (
  events=$SOFTWARE_EVENTS_FILE
  stop=$SOFTWARE_EVENTS_STOP
  verbose=${BOOTSTRAP_VERBOSE:-0}
  interval=${SOFTWARE_HEARTBEAT_INTERVAL:-30}
  case "$interval" in *[!0-9]*) interval=30 ;; esac
  # POSIX/bash arithmetic reads a leading zero as octal ("08" would abort the
  # renderer mid-loop) and a zero interval would spin the catch-up loop below
  # forever, so strip leading zeros and bound the value before any arithmetic.
  interval=${interval#"${interval%%[!0]*}"}
  if [ -z "$interval" ] || [ "$interval" -eq 0 ] || [ "${#interval}" -gt 9 ]; then
    interval=30
  fi
  tab=$(printf '\t')
  pending_label=''
  pending_since=0
  pending_shown=0
  next_heartbeat=0
  tty_capable=0
  if [ -t 3 ] && [ "${TERM:-dumb}" != dumb ]; then
    tty_capable=1
  fi
  exec 4<"$events"
  while :; do
    # Snapshot the stop marker at the START of the iteration, before draining.
    # The parent writes the marker only after the installer exits, so a final
    # event appended after the read loop below hits EOF is still drained on the
    # next pass; an end-of-loop marker check alone could exit and lose it.
    if [ -f "$stop" ]; then
      stop_seen=1
    else
      stop_seen=0
    fi
    while IFS= read -r event <&4; do
      [ -n "$event" ] || continue
      state=${event%%"$tab"*}
      label=${event#*"$tab"}
      case "$state" in
        start)
          if [ "$verbose" = 0 ]; then
            if [ "$tty_capable" = 1 ] && [ "$pending_shown" = 1 ]; then
              printf '\033[A\r\033[K%s\n' "→ $label" >&3
            else
              printf '%s\n' "→ $label" >&3
            fi
            pending_shown=1
          fi
          pending_label=$label
          pending_since=$(date +%s)
          next_heartbeat=$((pending_since + interval))
          ;;
        done|skip|fail)
          if [ "$verbose" = 0 ]; then
            case "$state" in
              done) color=$GREEN; symbol='✓' ;;
              skip) color=''; symbol='–' ;;
              fail) color=$YELLOW; symbol='!' ;;
            esac
            if [ "$tty_capable" = 1 ] && [ "$pending_shown" = 1 ]; then
              printf '\033[A\r\033[K%s%s %s%s\n' "$color" "$symbol" "$label" "$RESET" >&3
            else
              printf '%s%s %s%s\n' "$color" "$symbol" "$label" "$RESET" >&3
            fi
            pending_shown=0
          fi
          pending_label=''
          ;;
      esac
    done
    if [ "$verbose" = 0 ] && [ -n "$pending_label" ]; then
      now=$(date +%s)
      if [ "$now" -ge "$next_heartbeat" ]; then
        if [ "$tty_capable" = 1 ] && [ "$pending_shown" = 1 ]; then
          printf '\033[A\r\033[K  … %s (%ss)\n' \
            "$pending_label" "$((now - pending_since))" >&3
        else
          printf '  … %s (%ss)\n' "$pending_label" "$((now - pending_since))" >&3
        fi
        while [ "$now" -ge "$next_heartbeat" ]; do
          next_heartbeat=$((next_heartbeat + interval))
        done
      fi
    fi
    if [ "$stop_seen" = 1 ]; then
      exit 0
    fi
    sleep 1
  done
)

start_software_renderer() {
  software_renderer &
  SOFTWARE_RENDERER_PID=$!
}

stop_software_renderer() {
  # $1 = kill: stop immediately (signal path); otherwise let it drain first.
  if [ -n "$SOFTWARE_RENDERER_PID" ]; then
    : >"$SOFTWARE_EVENTS_STOP" 2>/dev/null || true
    if [ "${1:-}" = kill ]; then
      kill "$SOFTWARE_RENDERER_PID" 2>/dev/null || true
    fi
    wait "$SOFTWARE_RENDERER_PID" 2>/dev/null || true
    SOFTWARE_RENDERER_PID=''
  fi
  unset BOOTSTRAP_SOFTWARE_PROGRESS_FILE
}

stop_background() {
  for background_pid in "$HEARTBEAT_PID" "$SUDO_KEEPALIVE_PID" "$FOLLOW_PID"; do
    if [ -n "$background_pid" ]; then
      kill "$background_pid" 2>/dev/null || true
      wait "$background_pid" 2>/dev/null || true
    fi
  done
  stop_software_renderer kill
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
  # The software stage instead runs the app-by-app progress renderer, whose
  # current-operation heartbeat replaces the generic stage heartbeat.
  if [ "$BOOTSTRAP_STAGE" = software ]; then
    export BOOTSTRAP_SOFTWARE_PROGRESS_FILE="$SOFTWARE_EVENTS_FILE"
    start_software_renderer
  else
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
  fi
  # Keep installers in the foreground: background jobs inherit ignored SIGINT,
  # which would make Ctrl-C leave package managers running behind the summary.
  stage_status=0
  if have systemd-inhibit; then
    systemd-inhibit --what=idle:sleep --who=config-bootstrap --why="Running $label" \
      /usr/bin/env bash "$path" </dev/null || stage_status=$?
  else
    /usr/bin/env bash "$path" </dev/null || stage_status=$?
  fi
  if [ "$BOOTSTRAP_STAGE" = software ]; then
    # The renderer exits after draining everything written before the stop
    # file, so app rows always precede this stage's own result line.
    stop_software_renderer
  else
    kill "$HEARTBEAT_PID" 2>/dev/null || true
    wait "$HEARTBEAT_PID" 2>/dev/null || true
    HEARTBEAT_PID=''
  fi
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
