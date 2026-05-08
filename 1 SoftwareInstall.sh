#!/usr/bin/env bash
set -uo pipefail

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

install_pi() {
  if has_command pi; then
    log "pi is already installed."
    return 0
  fi

  if ! has_command npm; then
    warn "npm not found; cannot install pi."
    return 0
  fi

  run_or_warn "npm install pi" npm install -g @mariozechner/pi-coding-agent
}

install_rtk_official() {
  if has_command rtk; then
    log "RTK is already installed."
    return 0
  fi

  if has_command brew; then
    run_or_warn "Homebrew install rtk" brew install rtk
    return 0
  fi

  log "Installing RTK using the official installer."
  curl -fsSL https://raw.githubusercontent.com/rtk-ai/rtk/refs/heads/master/install.sh | sh \
    || warn "RTK official installer failed."
}

verify_rtk() {
  if has_command rtk; then
    rtk --version >/dev/null 2>&1 || warn "rtk command is installed but failed to run."
  else
    warn "rtk not found; pi rtk bash rewrite extension requires rtk in PATH."
  fi
}

install_zed_linux() {
  if has_command zed; then
    log "Zed is already installed."
    return 0
  fi

  log "Installing Zed editor using the official installer."
  curl -fsSL https://zed.dev/install.sh | sh || warn "Zed installer failed."
}

apt_package_installed() {
  dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q "install ok installed"
}

apt_install_if_missing() {
  local package="$1"

  if apt_package_installed "$package"; then
    log "${package} is already installed."
    return 0
  fi

  run_or_warn "apt install ${package}" sudo apt-get install -y "$package"
}

install_1password_apt_repo() {
  log "Ensuring 1Password apt repository is configured."

  curl -fsS https://downloads.1password.com/linux/keys/1password.asc \
    | sudo gpg --dearmor --batch --yes -o /usr/share/keyrings/1password-archive-keyring.gpg \
    || warn "Install 1Password apt key failed."

  printf '%s\n' 'deb [signed-by=/usr/share/keyrings/1password-archive-keyring.gpg] https://downloads.1password.com/linux/debian/amd64 stable main' \
    | sudo tee /etc/apt/sources.list.d/1password.list >/dev/null \
    || warn "Configure 1Password apt source failed."

  run_or_warn "create 1Password debsig policy directory" sudo mkdir -p /etc/debsig/policies/AC2D62742012EA22/
  curl -fsS https://downloads.1password.com/linux/debian/debsig/1password.pol \
    | sudo tee /etc/debsig/policies/AC2D62742012EA22/1password.pol >/dev/null \
    || warn "Install 1Password debsig policy failed."

  run_or_warn "create 1Password debsig key directory" sudo mkdir -p /etc/debsig/keys/AC2D62742012EA22/
  curl -fsS https://downloads.1password.com/linux/keys/1password.asc \
    | sudo gpg --dearmor --batch --yes -o /etc/debsig/keys/AC2D62742012EA22/1password.gpg \
    || warn "Install 1Password debsig key failed."
}

install_ubuntu_packages() {
  log "Updating apt repositories."
  run_or_warn "apt update" sudo apt-get update

  log "Ensuring core packages are installed with apt."
  local package
  for package in git tmux fish alacritty vim curl gnupg lsb-release nodejs npm; do
    apt_install_if_missing "$package"
  done

  install_rtk_official
  verify_rtk
  install_pi

  if has_command lspci && lspci | grep -Eq "Intel.*(Graphics|VGA)"; then
    apt_install_if_missing mesa-vulkan-drivers
  fi

  install_zed_linux
  install_1password_apt_repo

  log "Updating apt repositories after 1Password repo setup."
  run_or_warn "apt update after adding 1Password repository" sudo apt-get update
  for package in 1password 1password-cli; do
    apt_install_if_missing "$package"
  done
}

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

install_arch_1password() {
  if pacman_package_installed 1password || pacman_package_installed 1password-beta; then
    log "1Password is already installed."
  elif pacman -Si 1password-beta >/dev/null 2>&1; then
    pacman_install_if_missing 1password-beta
  elif pacman -Si 1password >/dev/null 2>&1; then
    pacman_install_if_missing 1password
  elif has_command yay; then
    run_or_warn "yay install 1password" yay -S --needed --noconfirm 1password
  else
    warn "Cannot install 1Password: package unavailable and yay not found."
  fi

  if pacman_package_installed 1password-cli; then
    log "1password-cli is already installed."
  elif pacman -Si 1password-cli >/dev/null 2>&1; then
    pacman_install_if_missing 1password-cli
  elif has_command yay; then
    run_or_warn "yay install 1password-cli" yay -S --needed --noconfirm 1password-cli
  else
    warn "Cannot install 1Password CLI: package unavailable and yay not found."
  fi
}

install_arch_packages() {
  log "Refreshing pacman repositories."
  run_or_warn "pacman refresh" sudo pacman -Syu --noconfirm

  log "Ensuring core packages are installed with pacman."
  local package
  for package in git tmux fish alacritty vim curl gnupg openssh nodejs npm; do
    pacman_install_if_missing "$package"
  done

  install_rtk_official
  verify_rtk
  install_pi

  if has_command lspci && lspci | grep -Eq "Intel.*(Graphics|VGA)"; then
    pacman_install_if_missing vulkan-intel
  fi

  install_zed_linux
  install_arch_1password
}

ensure_homebrew() {
  if has_command brew; then
    log "Homebrew is already installed."
    return 0
  fi

  log "Installing Homebrew."
  if ! /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"; then
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

brew_formula_installed() {
  "$BREW_BIN" list --formula "$1" >/dev/null 2>&1
}

brew_cask_installed() {
  "$BREW_BIN" list --cask "$1" >/dev/null 2>&1
}

app_installed() {
  local app_name="$1"
  [ -d "/Applications/${app_name}.app" ]
}

brew_install_formula_if_missing() {
  local package="$1"

  if brew_formula_installed "$package"; then
    log "${package} is already installed."
    return 0
  fi

  run_or_warn "Homebrew install ${package}" "$BREW_BIN" install "$package"
}

brew_install_cask_if_missing() {
  local cask="$1"
  shift
  local install_args=("$@")

  if brew_cask_installed "$cask"; then
    log "${cask} is already installed."
    return 0
  fi

  run_or_warn "Homebrew cask install ${cask}" "$BREW_BIN" install --cask "${install_args[@]}"
}

configure_homebrew_node24() {
  local node24_prefix=""
  local node_version=""
  local npm_version=""

  node24_prefix="$("$BREW_BIN" --prefix node@24 2>/dev/null || true)"
  if [ -z "$node24_prefix" ]; then
    warn "Homebrew node@24 prefix not found."
    return 0
  fi

  export PATH="${node24_prefix}/bin:${PATH}"

  if has_command node; then
    node_version="$(node -v 2>/dev/null || true)"
    if [ "$node_version" = "v24.15.0" ]; then
      log "Node.js version verified: ${node_version}."
    else
      warn "Expected Node.js v24.15.0 from Homebrew node@24, found ${node_version:-unknown}."
    fi
  else
    warn "node not found after installing Homebrew node@24. Add ${node24_prefix}/bin to PATH."
  fi

  if has_command npm; then
    npm_version="$(npm -v 2>/dev/null || true)"
    if [ "$npm_version" = "11.12.1" ]; then
      log "npm version verified: ${npm_version}."
    else
      warn "Expected npm 11.12.1 from Homebrew node@24, found ${npm_version:-unknown}."
    fi
  else
    warn "npm not found after installing Homebrew node@24. Add ${node24_prefix}/bin to PATH."
  fi
}

install_macos_packages() {
  ensure_homebrew || return 0

  BREW_BIN="$(command -v brew)"

  log "Updating Homebrew."
  run_or_warn "Homebrew update" "$BREW_BIN" update

  log "Ensuring CLI packages are installed with Homebrew."
  local package
  for package in git tmux fish vim 1password-cli rtk node@24; do
    brew_install_formula_if_missing "$package"
  done

  configure_homebrew_node24
  verify_rtk
  install_pi

  log "Ensuring applications are installed with Homebrew Cask."
  local cask
  for cask in alacritty zed; do
    brew_install_cask_if_missing "$cask" "$cask"
  done
  brew_install_cask_if_missing aerospace nikitabobko/tap/aerospace

  # Check 1Password more carefully - only install via brew if not already in /Applications
  if brew_cask_installed 1password; then
    log "1Password is already installed via Homebrew Cask."
  elif app_installed "1Password"; then
    log "1Password app already exists in /Applications (installed outside Homebrew)."
  else
    run_or_warn "Homebrew cask install 1password" "$BREW_BIN" install --cask 1password
  fi

  # Remove quarantine attribute from Alacritty to allow it to open without prompts
  # Only remove if the quarantine attribute is currently present (idempotent)
  if [ -d "/Applications/Alacritty.app" ]; then
    if xattr -p com.apple.quarantine /Applications/Alacritty.app >/dev/null 2>&1; then
      run_or_warn "Remove quarantine from Alacritty.app" sudo xattr -r -d com.apple.quarantine /Applications/Alacritty.app
    fi
  fi
}

setup_1password_account() {
  log "Checking 1Password CLI account setup."

  if ! has_command op; then
    warn "1Password CLI not found; run 'op account add' after installing it."
    return 0
  fi

  if op whoami >/dev/null 2>&1; then
    log "Already signed in to 1Password CLI."
    return 0
  fi

  log "1Password CLI not signed in. Running 'op account add' (can be skipped)."
  op account add || warn "1Password sign-in skipped or failed; run 'op account add' manually before running 2 Keys.sh."
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
  local uname_s=""
  local os_id=""
  local os_like=""

  uname_s="$(uname -s 2>/dev/null || true)"

  case "$uname_s" in
    Darwin)
      install_macos_packages
      ;;
    Linux)
      if [ -f /etc/os-release ]; then
        # shellcheck disable=SC1091
        . /etc/os-release
        os_id="${ID:-}"
        os_like="${ID_LIKE:-}"
      else
        warn "Unable to detect Linux distribution."
      fi

      case " ${os_id} ${os_like} " in
        *" ubuntu "*|*" debian "*)
          install_ubuntu_packages
          ;;
        *" arch "*)
          install_arch_packages
          ;;
        *)
          warn "Unsupported Linux distribution: ${os_id:-unknown}."
          ;;
      esac
      ;;
    *)
      warn "Unsupported operating system: ${uname_s:-unknown}."
      ;;
  esac

  setup_1password_account
  print_summary
  return 0
}

main "$@"
