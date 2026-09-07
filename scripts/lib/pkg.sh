# Package-manager helpers for pacman and Homebrew.
# Requires lib/report.sh and lib/common.sh to be sourced first.

pacman_package_installed() {
  pacman -Q "$1" >/dev/null 2>&1
}

pacman_install_if_missing() {
  local package="$1"

  if pacman_package_installed "$package"; then
    log "${package} is already installed."
    report_software_progress skip "${package} already installed"
    return 0
  fi

  progress_step "Installing ${package}…" "${package} installed" \
    "${package} installation failed" \
    "pacman install ${package}" sudo pacman -S --needed --noconfirm "$package"
}

# Installs from the repos when possible, otherwise from the AUR via yay.
arch_install_if_missing() {
  local package="$1"

  if pacman_package_installed "$package"; then
    log "${package} is already installed."
    report_software_progress skip "${package} already installed"
  elif pacman -Si "$package" >/dev/null 2>&1; then
    pacman_install_if_missing "$package"
  elif has_command yay; then
    progress_step "Installing ${package}…" "${package} installed" \
      "${package} installation failed" \
      "yay install ${package}" yay -S --needed --noconfirm "$package"
  else
    warn "Cannot install ${package}: package unavailable and yay not found."
    report_software_progress fail "${package} installation failed"
  fi
}

ensure_homebrew() {
  if has_command brew; then
    log "Homebrew is already installed."
    report_software_progress skip 'Homebrew already installed'
    return 0
  fi

  report_software_progress start 'Installing Homebrew…'
  log "Installing Homebrew non-interactively."
  if ! NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"; then
    warn "Homebrew installer failed."
    report_software_progress fail 'Homebrew installation failed'
    return 1
  fi

  if [ -x /opt/homebrew/bin/brew ]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  elif [ -x /usr/local/bin/brew ]; then
    eval "$(/usr/local/bin/brew shellenv)"
  fi

  if ! has_command brew; then
    warn "Homebrew installed but brew command not found in PATH."
    report_software_progress fail 'Homebrew installation failed'
    return 1
  fi

  report_software_progress done 'Homebrew installed'
}

brew_install_formula_if_missing() {
  local package="$1"

  if brew list --formula "$package" >/dev/null 2>&1; then
    log "${package} is already installed."
    report_software_progress skip "${package} already installed"
    return 0
  fi

  progress_step "Installing ${package}…" "${package} installed" \
    "${package} installation failed" \
    "Homebrew install ${package}" brew install "$package"
}

brew_install_cask_if_missing() {
  local cask="$1"
  local name="$cask"
  shift

  # Friendly names for apps people know by brand; the rest keep the cask name.
  case "$cask" in
    zed) name='Zed' ;;
    1password) name='1Password' ;;
  esac

  if brew list --cask "$cask" >/dev/null 2>&1; then
    log "${cask} is already installed."
    report_software_progress skip "${name} already installed"
    return 0
  fi

  progress_step "Installing ${name}…" "${name} installed" \
    "${name} installation failed" \
    "Homebrew cask install ${cask}" brew install --cask "$@"
}
