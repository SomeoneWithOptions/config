# Generic logging/dispatch helpers shared by the numbered scripts.
# Requires lib/report.sh to be sourced first (warn/note call report_warning/report_action).

ERRORS=()
# Steps a human has to finish later (logins, mostly). Never blocks the install.
NOTES=()

log() {
  printf "[%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$*"
}

warn() {
  local message="$*"
  ERRORS+=("$message")
  report_warning "$message"
}

run_or_warn() {
  local description="$1"
  shift

  if ! "$@"; then
    warn "${description} failed."
    return 1
  fi
}

note() {
  NOTES+=("$2")
  report_action "$@"
}

has_command() {
  command -v "$1" >/dev/null 2>&1
}

# Emits start/done/fail progress around one warned command. Labels are the
# complete human-readable operation text; the state only picks the symbol.
progress_step() {
  local start_label="$1" done_label="$2" fail_label="$3"
  shift 3
  report_software_progress start "$start_label"
  # The explicit return keeps cosmetic reporting (which reports its own append
  # failures) from ever masking or changing the command's result.
  if run_or_warn "$@"; then
    report_software_progress done "$done_label"
    return 0
  fi
  report_software_progress fail "$fail_label"
  return 1
}
