#!/usr/bin/env bash
set -uo pipefail

# Installs software on the only two machine types this repo configures:
# macOS (Homebrew) and Omarchy/Arch (pacman + yay).

# Keep installers non-interactive. Commands may still ask for sudo credentials when needed.
export HOMEBREW_NO_ENV_HINTS=1
export HOMEBREW_NO_ANALYTICS=1
export NONINTERACTIVE=1

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=scripts/lib/report.sh
. "$SCRIPT_DIR/scripts/lib/report.sh"
# shellcheck source=scripts/lib/common.sh
. "$SCRIPT_DIR/scripts/lib/common.sh"
# shellcheck source=scripts/lib/pkg.sh
. "$SCRIPT_DIR/scripts/lib/pkg.sh"
# shellcheck source=scripts/install/tools.sh
. "$SCRIPT_DIR/scripts/install/tools.sh"
# shellcheck source=scripts/install/arch.sh
. "$SCRIPT_DIR/scripts/install/arch.sh"
# shellcheck source=scripts/install/macos.sh
. "$SCRIPT_DIR/scripts/install/macos.sh"

print_summary() {
  # Bootstrap owns the combined summary, after all five scripts finish.
  [ -z "${BOOTSTRAP_REPORT_DIR:-}" ] || return 0
  if [ "${#ERRORS[@]}" -eq 0 ]; then
    log "Software installation completed with no warnings."
  else
    log "Software installation completed with ${#ERRORS[@]} warning(s):"
    local error
    for error in "${ERRORS[@]}"; do
      printf "  - %s\n" "$error"
    done
  fi

  if [ "${#NOTES[@]}" -gt 0 ]; then
    log "Manual follow-up(s) left for you, none of them blocked this install:"
    local pending
    for pending in "${NOTES[@]}"; do
      printf "  - %s\n" "$pending"
    done
  fi
}

main() {
  local status=0

  if ! has_command curl; then
    warn "curl not found; it is required by every installer here."
  fi

  case "$(uname -s 2>/dev/null || true)" in
    Darwin)
      install_macos_packages
      ;;
    Linux)
      if has_command pacman; then
        install_arch_packages || status=$?
      else
        warn "Unsupported Linux distribution. This repo configures Omarchy/Arch only."
      fi
      ;;
    *)
      warn "Unsupported operating system. This repo configures macOS and Omarchy/Arch only."
      ;;
  esac

  print_summary
  return "$status"
}

main "$@"
