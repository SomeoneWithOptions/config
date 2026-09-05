#!/usr/bin/env bash
set -uo pipefail

# Installs software on the only two machine types this repo configures:
# macOS (Homebrew) and Omarchy/Arch (pacman + yay).

# Keep installers non-interactive. Commands may still ask for sudo credentials when needed.
export HOMEBREW_NO_ENV_HINTS=1
export HOMEBREW_NO_ANALYTICS=1
export NONINTERACTIVE=1

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib/report.sh
. "$SCRIPT_DIR/lib/report.sh"

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

# --- Cross-platform installers ---------------------------------------------

install_pi() {
  if has_command pi; then
    log "pi is already installed."
    return 0
  fi

  log "Installing pi using the official installer."
  curl -fsSL https://pi.dev/install.sh | sh || warn "Pi official installer failed."
}

install_commiter() {
  if [ -x "$HOME/.local/bin/c" ]; then
    log "commiter is already installed."
    return 0
  fi

  log "Installing commiter using its unattended installer."
  curl -fsSL https://go.sanetomore.com/commiter | sh || warn "commiter installer failed."
}

install_loom_omarchy_linux() {
  if has_command loom; then
    log "loom-omarchy-linux is already installed."
    return 0
  fi

  log "Installing loom-omarchy-linux using its unattended installer."
  curl -fsSL https://raw.githubusercontent.com/SomeoneWithOptions/loom-omarchy-linux/main/install.sh | bash \
    || warn "loom-omarchy-linux installer failed."
}

install_linear_omarchy_plugin() {
  local install_dir="$HOME/.config/omarchy/plugins/andres.linear"
  if [ -f "$install_dir/manifest.json" ] && [ -x "$install_dir/bin/omarchy-linear-setup" ]; then
    log "linear-omarchy-plugin is already installed."
    report_linear_action
    return 0
  fi

  log "Installing linear-omarchy-plugin using its unattended installer."
  curl -fsSL https://raw.githubusercontent.com/SomeoneWithOptions/linear-omarchy-plugin/main/install.sh \
    | bash -s -- --yes || warn "linear-omarchy-plugin installer failed."
  report_linear_action
}

install_npm_cli() {
  local package="$1"
  local command_name="$2"

  if [ "$(uname -s)" = "Linux" ]; then
    run_or_warn "omarchy mise install ${package}" \
      omarchy-mise-install "npm:${package}" "$command_name"
  elif has_command "$command_name"; then
    log "${command_name} is already installed."
  elif has_command npm; then
    run_or_warn "npm install ${package}" npm install --global "$package"
  else
    warn "npm not found; cannot install ${command_name}."
  fi
}

install_personal_dev_tools() {
  install_commiter
  install_npm_cli @google/clasp clasp
  install_npm_cli vercel vercel
}

install_rtk() {
  if has_command rtk; then
    log "RTK is already installed."
  elif has_command brew; then
    run_or_warn "Homebrew install rtk" brew install rtk
  else
    log "Installing RTK using the official installer."
    curl -fsSL https://raw.githubusercontent.com/rtk-ai/rtk/refs/heads/master/install.sh | sh \
      || warn "RTK official installer failed."
  fi

  # pi's rtk bash rewrite extension needs rtk in PATH, so verify it actually runs.
  if has_command rtk; then
    rtk --version >/dev/null 2>&1 || warn "rtk command is installed but failed to run."
  else
    warn "rtk not found; pi rtk bash rewrite extension requires rtk in PATH."
  fi
}

# --- Arch / Omarchy ---------------------------------------------------------

pacman_package_installed() {
  pacman -Q "$1" >/dev/null 2>&1
}

pacman_install_if_missing() {
  local package="$1"

  if pacman_package_installed "$package"; then
    log "${package} is already installed."
    return 0
  fi

  run_or_warn "pacman install ${package}" sudo pacman -S --needed --noconfirm "$package"
}

# Installs from the repos when possible, otherwise from the AUR via yay.
arch_install_if_missing() {
  local package="$1"

  if pacman_package_installed "$package"; then
    log "${package} is already installed."
  elif pacman -Si "$package" >/dev/null 2>&1; then
    pacman_install_if_missing "$package"
  elif has_command yay; then
    run_or_warn "yay install ${package}" yay -S --needed --noconfirm "$package"
  else
    warn "Cannot install ${package}: package unavailable and yay not found."
  fi
}

# `omarchy default editor` ends in a desktop notification and returns the toast's
# exit status. Right after `omarchy update` restarts the shell, the notification
# daemon is not back on the bus yet, so the call reports failure even though the
# editor was written. Verify the setting instead of trusting the exit code.
set_default_editor() {
  local editor="$1"

  omarchy default editor "$editor" >/dev/null 2>&1
  [ "$(omarchy default editor 2>/dev/null)" = "$editor" ] && return 0

  warn "set ${editor} as default editor failed."
  return 1
}

remove_stock_omarchy_apps() {
  log "Removing stock Omarchy apps not wanted on this laptop config."

  # omarchy-launch-editor otherwise falls back to nvim after it is removed.
  set_default_editor vim
  run_or_warn "remove unwanted Omarchy packages" omarchy pkg drop \
    omarchy-nvim neovim \
    obsidian xournalpp aether cliamp kdenlive pinta
}

# `omarchy install service tailscale` ends in a bare `tailscale up`, which blocks
# the whole install until the device is authenticated in a browser. Every other
# step of that installer is unattended, so run those here and leave the login for
# later -- or pass TS_AUTHKEY to finish it now.
install_arch_tailscale() {
  if pacman_package_installed tailscale; then
    log "tailscale is already installed."
  elif ! run_or_warn "omarchy install tailscale package" omarchy pkg add tailscale; then
    return 0
  fi

  run_or_warn "enable tailscaled" sudo systemctl enable --now tailscaled.service
  # A prefs edit: works while logged out and survives a later `tailscale up`.
  run_or_warn "allow ${USER} to manage Tailscale" sudo tailscale set --operator="$USER"
  run_or_warn "enable Taildrop receive unit" \
    systemctl --user enable omarchy-tailscale-receive.service
  run_or_warn "install Tailscale web app" omarchy-webapp-install "Tailscale" \
    "https://login.tailscale.com/admin/machines" \
    https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/tailscale-light.png
  # No `omarchy-plugin-enable omarchy.tailscale`: the bar runs this repo's own
  # andres.tailscale clone, wired up by omarchy/shell.json.

  # `tailscale status` exits non-zero while logged out or while tailscaled is down.
  if tailscale status >/dev/null 2>&1; then
    log "Tailscale is already logged in."
    run_or_warn "start Taildrop receive" \
      systemctl --user start omarchy-tailscale-receive.service
    return 0
  fi

  if [ -n "${TS_AUTHKEY:-}" ]; then
    run_or_warn "tailscale up with TS_AUTHKEY" \
      sudo tailscale up --accept-routes --auth-key "$TS_AUTHKEY"
    run_or_warn "start Taildrop receive" \
      systemctl --user start omarchy-tailscale-receive.service
    return 0
  fi

  note tailscale 'Tailscale → sign in' \
    'Run: sudo tailscale up --accept-routes' \
    'Then: systemctl --user start omarchy-tailscale-receive.service'
}

install_arch_1password() {
  run_or_warn "omarchy install service 1password" omarchy install service 1password


  # The installer opens the 1Password app in the background, but signing in is a
  # human step. `5 Keys.sh` skips the SSH key when the CLI is not signed in.
  if [ "${BOOTSTRAP_KEYS:-1}" = 1 ] && ! op whoami >/dev/null 2>&1; then
    report_keys_action
  fi
}

update_arch_system() {
  local update_log="${OMARCHY_UPDATE_LOG_FILE:-/tmp/omarchy-update.log}"
  local update_status

  log "Updating Omarchy and system packages through the supported update entrypoint."
  # Omarchy normally wraps itself in script(1) for /tmp/omarchy-update.log. That
  # creates a new pseudo-TTY with a separate sudo ticket, defeating bootstrap's
  # one-time sudo authentication. Keep update + sudo on this TTY, while tee still
  # supplies Omarchy's expected diagnostics log and bootstrap's private transcript.
  if ! (umask 077; : >"$update_log") || ! chmod 600 "$update_log"; then
    warn "Cannot create private Omarchy update log at ${update_log}; package operations were stopped."
    note system-update 'Omarchy update → retry' \
      "Make ${update_log} writable, then rerun bootstrap."
    return 1
  fi
  if OMARCHY_UPDATE_LOGGED=1 omarchy update -y 2>&1 | tee "$update_log"; then
    return 0
  else
    update_status=$?
  fi

  warn "Omarchy system update failed; subsequent package operations were stopped."
  note system-update 'Omarchy update → retry' \
    'Review the detailed bootstrap log and correct the update error.' \
    'Run: omarchy update -y' \
    'Then rerun bootstrap.'
  return "$update_status"
}

install_arch_packages() {
  # Do not remove or install packages after a failed full-system update: package
  # databases or installed packages may be mid-transition or out of sync.
  update_arch_system || return $?

  remove_stock_omarchy_apps

  log "Ensuring packages are installed with pacman/yay."
  local package
  # Omarchy's own base/hardware installs already cover git, tmux, quickshell(-git)
  # and vulkan-{intel,radeon,asahi} for the detected GPU; curl/gnupg/openssh arrive
  # as dependencies. Listing them here was a no-op.
  #
  # libfprint here is `libfprint`, never `libfprint-git`: the AUR build
  # provides+conflicts libfprint, so `pacman -S --noconfirm` answers the conflict
  # prompt N and aborts the whole step -- and it is a downgrade besides.
  for package in \
    fish \
    alacritty \
    ghostty \
    vim \
    terraform \
    aws-cli-v2 \
    google-cloud-cli \
    bind \
    fwupd \
    cmatrix \
    vlc \
    gsfonts \
    ttf-liberation \
    libfprint \
    fprintd \
    usbutils \
    libcamera \
    libcamera-ipa \
    libcamera-tools \
    pipewire-libcamera \
    gst-plugin-libcamera \
    v4l2loopback-dkms; do
    arch_install_if_missing "$package"
  done

  # Use Omarchy's mise config instead of owning ~/.config/mise/config.toml.
  run_or_warn "omarchy install dev-env node" omarchy install dev-env node
  run_or_warn "omarchy install dev-env go" omarchy install dev-env go
  # omazed 2.0.1's setup still reads pre-Quattro paths; ConfigFiles installs
  # the compatible theme hook instead.
  run_or_warn "omarchy install Zed packages" omarchy pkg add zed omazed
  run_or_warn "omarchy install browser zen" omarchy install browser zen

  # The bar ships an `andres.tailscale` widget, so the binary has to exist on a
  # fresh laptop. This also enables tailscaled and Taildrop.
  install_arch_tailscale

  install_arch_1password
  install_rtk
  # No install_pi here: Omarchy mise-installs `pi` during setup (install/user/mise.sh).
  # The macOS branch still needs the upstream installer.
  install_personal_dev_tools
  install_loom_omarchy_linux
  install_linear_omarchy_plugin

  # Individual optional install failures are warnings. Only failed system update
  # returns non-zero, above, because continuing package work would be unsafe.
  return 0
}

# --- macOS ------------------------------------------------------------------

ensure_homebrew() {
  if has_command brew; then
    log "Homebrew is already installed."
    return 0
  fi

  log "Installing Homebrew non-interactively."
  if ! NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"; then
    warn "Homebrew installer failed."
    return 1
  fi

  if [ -x /opt/homebrew/bin/brew ]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  elif [ -x /usr/local/bin/brew ]; then
    eval "$(/usr/local/bin/brew shellenv)"
  fi

  has_command brew || { warn "Homebrew installed but brew command not found in PATH."; return 1; }
}

brew_install_formula_if_missing() {
  local package="$1"

  if brew list --formula "$package" >/dev/null 2>&1; then
    log "${package} is already installed."
    return 0
  fi

  run_or_warn "Homebrew install ${package}" brew install "$package"
}

brew_install_cask_if_missing() {
  local cask="$1"
  shift

  if brew list --cask "$cask" >/dev/null 2>&1; then
    log "${cask} is already installed."
    return 0
  fi

  run_or_warn "Homebrew cask install ${cask}" brew install --cask "$@"
}

configure_homebrew_node24() {
  local node24_prefix=""

  node24_prefix="$(brew --prefix node@24 2>/dev/null || true)"
  if [ -z "$node24_prefix" ]; then
    warn "Homebrew node@24 prefix not found."
    return 0
  fi

  export PATH="${node24_prefix}/bin:${PATH}"

  has_command node || warn "node not found after installing Homebrew node@24. Add ${node24_prefix}/bin to PATH."
  has_command npm || warn "npm not found after installing Homebrew node@24. Add ${node24_prefix}/bin to PATH."
}

install_macos_packages() {
  ensure_homebrew || return 0

  log "Updating Homebrew."
  run_or_warn "Homebrew update" brew update

  log "Ensuring CLI packages are installed with Homebrew."
  local package
  for package in git gh tmux fish vim mise 1password-cli rtk node@24 google-cloud-sdk; do
    brew_install_formula_if_missing "$package"
  done

  configure_homebrew_node24
  run_or_warn "mise install Go" mise use -g go@latest
  install_rtk
  install_pi

  log "Ensuring applications are installed with Homebrew Cask."
  local cask
  for cask in alacritty ghostty zed; do
    brew_install_cask_if_missing "$cask" "$cask"
  done
  brew_install_cask_if_missing aerospace nikitabobko/tap/aerospace

  # 1Password is often installed outside Homebrew; do not install a second copy.
  if [ -d "/Applications/1Password.app" ]; then
    log "1Password app already exists in /Applications."
  else
    brew_install_cask_if_missing 1password 1password
  fi

  # Alacritty is quarantined on first install and prompts on launch. Idempotent:
  # only strip the attribute while it is still present.
  if [ -d "/Applications/Alacritty.app" ] && xattr -p com.apple.quarantine /Applications/Alacritty.app >/dev/null 2>&1; then
    run_or_warn "Remove quarantine from Alacritty.app" sudo xattr -r -d com.apple.quarantine /Applications/Alacritty.app
  fi

  install_personal_dev_tools
}

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
