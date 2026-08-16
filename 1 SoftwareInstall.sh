#!/usr/bin/env bash
set -uo pipefail

# Installs software on the only two machine types this repo configures:
# macOS (Homebrew) and Omarchy/Arch (pacman + yay).

# Keep installers non-interactive. Commands may still ask for sudo credentials when needed.
export HOMEBREW_NO_ENV_HINTS=1
export HOMEBREW_NO_ANALYTICS=1
export NONINTERACTIVE=1

ERRORS=()

log() {
  printf "[%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$*"
}

warn() {
  local message="$*"
  ERRORS+=("$message")
  log "WARNING: ${message}"
}

run_or_warn() {
  local description="$1"
  shift

  if ! "$@"; then
    warn "${description} failed."
    return 1
  fi
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

  log "Installing commiter using the official installer."
  curl -fsSL https://go.sanetomore.com/commiter | sh || warn "commiter installer failed."
}

install_npm_cli() {
  local package="$1"
  local command_name="$2"

  if has_command "$command_name"; then
    log "${command_name} is already installed."
  elif ! has_command npm; then
    warn "npm not found; cannot install ${command_name}."
  elif [ "$(uname -s)" = "Linux" ]; then
    run_or_warn "npm install ${package}" sudo npm install --global "$package"
  else
    run_or_warn "npm install ${package}" npm install --global "$package"
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

remove_stock_omarchy_apps() {
  log "Removing stock Omarchy apps not wanted on this laptop config."

  local package
  for package in signal-desktop obsidian xournalpp typora aether cliamp kdenlive spotify pinta; do
    if pacman_package_installed "$package"; then
      run_or_warn "pacman remove ${package}" sudo pacman -Rns --noconfirm "$package"
    fi
  done
}

install_arch_1password() {
  if pacman_package_installed 1password || pacman_package_installed 1password-beta; then
    log "1Password is already installed."
  else
    arch_install_if_missing 1password-beta
  fi

  arch_install_if_missing 1password-cli
}

install_arch_packages() {
  log "Refreshing pacman repositories."
  run_or_warn "pacman refresh" sudo pacman -Syu --noconfirm

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
    github-cli \
    fish \
    alacritty \
    ghostty \
    vim \
    nodejs \
    npm \
    zed \
    terraform \
    aws-cli-v2 \
    google-cloud-cli \
    bind \
    fwupd \
    cmatrix \
    vlc \
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

  run_or_warn "omarchy install browser zen" omarchy install browser zen

  # The bar ships an `andres.tailscale` widget, so the binary has to exist on a
  # fresh laptop. This also enables tailscaled and Taildrop.
  if ! has_command tailscale; then
    run_or_warn "omarchy install service tailscale" omarchy install service tailscale
  fi

  install_arch_1password
  install_rtk
  # No install_pi here: Omarchy mise-installs `pi` during setup (install/user/mise.sh).
  # The macOS branch still needs the upstream installer.
  install_personal_dev_tools
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
  for package in git gh tmux fish vim 1password-cli rtk node@24 google-cloud-sdk; do
    brew_install_formula_if_missing "$package"
  done

  configure_homebrew_node24
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
  if [ "${#ERRORS[@]}" -eq 0 ]; then
    log "Software installation completed with no warnings."
    return 0
  fi

  log "Software installation completed with ${#ERRORS[@]} warning(s):"
  local error
  for error in "${ERRORS[@]}"; do
    printf "  - %s\n" "$error"
  done
}

main() {
  if ! has_command curl; then
    warn "curl not found; it is required by every installer here."
  fi

  case "$(uname -s 2>/dev/null || true)" in
    Darwin)
      install_macos_packages
      ;;
    Linux)
      if has_command pacman; then
        install_arch_packages
      else
        warn "Unsupported Linux distribution. This repo configures Omarchy/Arch only."
      fi
      ;;
    *)
      warn "Unsupported operating system. This repo configures macOS and Omarchy/Arch only."
      ;;
  esac

  print_summary
  return 0
}

main "$@"
