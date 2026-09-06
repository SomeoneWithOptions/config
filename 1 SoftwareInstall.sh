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

# --- Cross-platform installers ---------------------------------------------

install_pi() {
  if has_command pi; then
    log "pi is already installed."
    report_software_progress skip 'pi already installed'
    return 0
  fi

  log "Installing pi using the official installer."
  report_software_progress start 'Installing pi…'
  # Runs under this script's pipefail: a failed download must not be masked by
  # the installer shell reading empty input.
  if curl -fsSL https://pi.dev/install.sh | sh; then
    report_software_progress done 'pi installed'
  else
    warn "Pi official installer failed."
    report_software_progress fail 'pi installation failed'
  fi
}

install_commiter() {
  if [ -x "$HOME/.local/bin/c" ]; then
    log "commiter is already installed."
    report_software_progress skip 'commiter already installed'
    return 0
  fi

  log "Installing commiter using its unattended installer."
  report_software_progress start 'Installing commiter…'
  if curl -fsSL https://go.sanetomore.com/commiter | sh; then
    report_software_progress done 'commiter installed'
  else
    warn "commiter installer failed."
    report_software_progress fail 'commiter installation failed'
  fi
}

install_loom_omarchy_linux() {
  if has_command loom; then
    log "loom-omarchy-linux is already installed."
    report_software_progress skip 'loom-omarchy-linux already installed'
    return 0
  fi

  log "Installing loom-omarchy-linux using its unattended installer."
  report_software_progress start 'Installing loom-omarchy-linux…'
  if curl -fsSL https://raw.githubusercontent.com/SomeoneWithOptions/loom-omarchy-linux/main/install.sh | bash; then
    report_software_progress done 'loom-omarchy-linux installed'
  else
    warn "loom-omarchy-linux installer failed."
    report_software_progress fail 'loom-omarchy-linux installation failed'
  fi
}

install_linear_omarchy_plugin() {
  local install_dir="$HOME/.config/omarchy/plugins/andres.linear"
  if [ -f "$install_dir/manifest.json" ] && [ -x "$install_dir/bin/omarchy-linear-setup" ]; then
    log "linear-omarchy-plugin is already installed."
    report_software_progress skip 'linear-omarchy-plugin already installed'
    report_linear_action
    return 0
  fi

  log "Installing linear-omarchy-plugin using its unattended installer."
  report_software_progress start 'Installing linear-omarchy-plugin…'
  if curl -fsSL https://raw.githubusercontent.com/SomeoneWithOptions/linear-omarchy-plugin/main/install.sh | bash -s -- --yes; then
    report_software_progress done 'linear-omarchy-plugin installed'
  else
    warn "linear-omarchy-plugin installer failed."
    report_software_progress fail 'linear-omarchy-plugin installation failed'
  fi
  report_linear_action
}

install_npm_cli() {
  local package="$1"
  local command_name="$2"

  if [ "$(uname -s)" = "Linux" ]; then
    progress_step "Installing ${command_name}…" "${command_name} installed" \
      "${command_name} installation failed" \
      "omarchy mise install ${package}" omarchy-mise-install "npm:${package}" "$command_name"
  elif has_command "$command_name"; then
    log "${command_name} is already installed."
    report_software_progress skip "${command_name} already installed"
  elif has_command npm; then
    progress_step "Installing ${command_name}…" "${command_name} installed" \
      "${command_name} installation failed" \
      "npm install ${package}" npm install --global "$package"
  else
    warn "npm not found; cannot install ${command_name}."
    report_software_progress fail "${command_name} not installed"
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
    report_software_progress skip 'rtk already installed'
  elif has_command brew; then
    progress_step 'Installing rtk…' 'rtk installed' 'rtk installation failed' \
      "Homebrew install rtk" brew install rtk
  else
    log "Installing RTK using the official installer."
    report_software_progress start 'Installing rtk…'
    if curl -fsSL https://raw.githubusercontent.com/rtk-ai/rtk/refs/heads/master/install.sh | sh; then
      report_software_progress done 'rtk installed'
    else
      warn "RTK official installer failed."
      report_software_progress fail 'rtk installation failed'
    fi
  fi

  # pi's rtk bash rewrite extension needs rtk in PATH, so verify it actually runs.
  if has_command rtk; then
    if ! rtk --version >/dev/null 2>&1; then
      warn "rtk command is installed but failed to run."
      report_software_progress fail 'rtk verification failed'
    fi
  else
    warn "rtk not found; pi rtk bash rewrite extension requires rtk in PATH."
    report_software_progress fail 'rtk verification failed'
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
  local failures=0

  log "Removing stock Omarchy apps not wanted on this laptop config."
  report_software_progress start 'Removing stock Omarchy apps…'

  # omarchy-launch-editor otherwise falls back to nvim after it is removed.
  set_default_editor vim || failures=$((failures + 1))
  run_or_warn "remove unwanted Omarchy packages" omarchy pkg drop \
    omarchy-nvim neovim \
    obsidian xournalpp aether cliamp kdenlive pinta || failures=$((failures + 1))

  # A warned substep must not report whole-operation success.
  if [ "$failures" -eq 0 ]; then
    report_software_progress done 'Stock Omarchy apps removed'
  else
    report_software_progress fail 'Stock Omarchy apps removal failed'
  fi
}

# `omarchy install service tailscale` ends in a bare `tailscale up`, which blocks
# the whole install until the device is authenticated in a browser. Every other
# step of that installer is unattended, so run those here and leave the login for
# later -- or pass TS_AUTHKEY to finish it now.
install_arch_tailscale() {
  local failures=0
  local logged_in=0

  if pacman_package_installed tailscale; then
    log "tailscale is already installed."
    report_software_progress skip 'Tailscale already installed'
  elif ! progress_step 'Installing Tailscale…' 'Tailscale installed' \
      'Tailscale installation failed' \
      "omarchy install tailscale package" omarchy pkg add tailscale; then
    return 0
  fi

  report_software_progress start 'Configuring Tailscale…'
  run_or_warn "enable tailscaled" sudo systemctl enable --now tailscaled.service \
    || failures=$((failures + 1))
  # A prefs edit: works while logged out and survives a later `tailscale up`.
  run_or_warn "allow ${USER} to manage Tailscale" sudo tailscale set --operator="$USER" \
    || failures=$((failures + 1))
  run_or_warn "enable Taildrop receive unit" \
    systemctl --user enable omarchy-tailscale-receive.service || failures=$((failures + 1))
  run_or_warn "install Tailscale web app" omarchy-webapp-install "Tailscale" \
    "https://login.tailscale.com/admin/machines" \
    https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/tailscale-light.png \
    || failures=$((failures + 1))
  # No `omarchy-plugin-enable omarchy.tailscale`: the bar runs this repo's own
  # andres.tailscale clone, wired up by omarchy/shell.json.

  # `tailscale status` exits non-zero while logged out or while tailscaled is down.
  if tailscale status >/dev/null 2>&1; then
    logged_in=1
    log "Tailscale is already logged in."
    run_or_warn "start Taildrop receive" \
      systemctl --user start omarchy-tailscale-receive.service || failures=$((failures + 1))
  elif [ -n "${TS_AUTHKEY:-}" ]; then
    run_or_warn "tailscale up with TS_AUTHKEY" \
      sudo tailscale up --accept-routes --auth-key "$TS_AUTHKEY" || failures=$((failures + 1))
    run_or_warn "start Taildrop receive" \
      systemctl --user start omarchy-tailscale-receive.service || failures=$((failures + 1))
  fi

  if [ "$failures" -eq 0 ]; then
    report_software_progress done 'Tailscale configured'
  else
    report_software_progress fail 'Tailscale configuration failed'
  fi

  # Sign-in stays a manual follow-up when no auth key was provided.
  if [ "$logged_in" = 0 ] && [ -z "${TS_AUTHKEY:-}" ]; then
    note tailscale 'Tailscale → sign in' \
      'Run: sudo tailscale up --accept-routes' \
      'Then: systemctl --user start omarchy-tailscale-receive.service'
  fi
}

install_arch_1password() {
  # The service wraps omarchy-pkg-add 1password 1password-cli and also installs
  # the 1Password Chromium extension policy and re-opens the app, so an already
  # installed pair is reconfigured through the same service instead of skipping
  # those side effects.
  if pacman_package_installed 1password && pacman_package_installed 1password-cli; then
    log "1Password is already installed; running the service to (re)configure it."
    report_software_progress start 'Configuring 1Password…'
    if run_or_warn "configure 1Password service" omarchy install service 1password; then
      report_software_progress done '1Password configured'
    else
      report_software_progress fail '1Password configuration failed'
    fi
  else
    # A failed install must still reach the sign-in action below, as before.
    progress_step 'Installing 1Password…' '1Password installed' \
      '1Password installation failed' \
      "omarchy install service 1password" omarchy install service 1password || true
  fi

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
  report_software_progress start 'Updating Omarchy and system packages…'
  # Omarchy normally wraps itself in script(1) for /tmp/omarchy-update.log. That
  # creates a new pseudo-TTY with a separate sudo ticket, defeating bootstrap's
  # one-time sudo authentication. Keep update + sudo on this TTY, while tee still
  # supplies Omarchy's expected diagnostics log and bootstrap's private transcript.
  #
  # Attach the controlling terminal to stdin when bootstrap itself was piped in
  # (curl ... | sh). omarchy-update-stay-awake picks its privilege runner via
  # "[[ -t 0 ]]": pipe stdin forces the pkexec path, and pkexec exec(3)s
  # systemd-inhibit in its own (now root-owned) process, which the unprivileged
  # stop step can never kill (EPERM) — leaving a leaked sleep inhibitor plus
  # "Failed to stop the Omarchy update sleep inhibitor.". With a TTY on stdin it
  # uses sudo, whose ticket is already warm from start_sudo_keepalive.
  local update_stdin=/dev/null
  if { true </dev/tty; } 2>/dev/null; then
    update_stdin=/dev/tty
  fi
  if ! (umask 077; : >"$update_log") || ! chmod 600 "$update_log"; then
    warn "Cannot create private Omarchy update log at ${update_log}; package operations were stopped."
    report_software_progress fail 'Omarchy system update failed'
    note system-update 'Omarchy update → retry' \
      "Make ${update_log} writable, then rerun bootstrap."
    return 1
  fi
  if OMARCHY_UPDATE_LOGGED=1 omarchy update -y <"$update_stdin" 2>&1 | tee "$update_log"; then
    report_software_progress done 'Omarchy and system packages updated'
    return 0
  else
    update_status=$?
  fi

  warn "Omarchy system update failed; subsequent package operations were stopped."
  report_software_progress fail 'Omarchy system update failed'
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
  progress_step 'Installing Node.js…' 'Node.js installed' 'Node.js installation failed' \
    "omarchy install dev-env node" omarchy install dev-env node
  progress_step 'Installing Go…' 'Go installed' 'Go installation failed' \
    "omarchy install dev-env go" omarchy install dev-env go
  # omazed 2.0.1's setup still reads pre-Quattro paths; ConfigFiles installs
  # the compatible theme hook instead.
  if pacman_package_installed zed && pacman_package_installed omazed; then
    log "zed and omazed are already installed."
    report_software_progress skip 'Zed already installed'
  else
    progress_step 'Installing Zed packages…' 'Zed packages installed' \
      'Zed packages installation failed' \
      "omarchy install Zed packages" omarchy pkg add zed omazed
  fi
  # `omarchy install browser zen` wraps omarchy-pkg-aur-add zen-browser-bin and
  # also installs the Firefox policy distribution and the Wayland environment
  # file, so an already installed browser is reconfigured through the same
  # installer instead of skipping those side effects.
  if pacman_package_installed zen-browser-bin; then
    log "zen-browser-bin is already installed; running the installer to (re)configure it."
    report_software_progress start 'Configuring Zen browser…'
    if run_or_warn "configure Zen browser" omarchy install browser zen; then
      report_software_progress done 'Zen browser configured'
    else
      report_software_progress fail 'Zen browser configuration failed'
    fi
  else
    progress_step 'Installing Zen browser…' 'Zen browser installed' \
      'Zen browser installation failed' \
      "omarchy install browser zen" omarchy install browser zen
  fi

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

configure_homebrew_node24() {
  local node24_prefix=""
  local failures=0

  report_software_progress start 'Configuring Node.js 24…'
  node24_prefix="$(brew --prefix node@24 2>/dev/null || true)"
  if [ -z "$node24_prefix" ]; then
    warn "Homebrew node@24 prefix not found."
    failures=$((failures + 1))
  else
    export PATH="${node24_prefix}/bin:${PATH}"

    if ! has_command node; then
      warn "node not found after installing Homebrew node@24. Add ${node24_prefix}/bin to PATH."
      failures=$((failures + 1))
    fi
    if ! has_command npm; then
      warn "npm not found after installing Homebrew node@24. Add ${node24_prefix}/bin to PATH."
      failures=$((failures + 1))
    fi
  fi

  if [ "$failures" -eq 0 ]; then
    report_software_progress done 'Node.js 24 configured'
  else
    report_software_progress fail 'Node.js 24 configuration failed'
  fi
}

install_macos_packages() {
  ensure_homebrew || return 0

  log "Updating Homebrew."
  progress_step 'Updating Homebrew…' 'Homebrew updated' 'Homebrew update failed' \
    "Homebrew update" brew update

  log "Ensuring CLI packages are installed with Homebrew."
  local package
  for package in git gh tmux fish vim mise 1password-cli rtk node@24 google-cloud-sdk; do
    brew_install_formula_if_missing "$package"
  done

  configure_homebrew_node24
  progress_step 'Installing Go…' 'Go installed' 'Go installation failed' \
    "mise install Go" mise use -g go@latest
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
    report_software_progress skip '1Password already installed'
  else
    brew_install_cask_if_missing 1password 1password
  fi

  # Alacritty is quarantined on first install and prompts on launch. Idempotent:
  # only strip the attribute while it is still present.
  if [ -d "/Applications/Alacritty.app" ] && xattr -p com.apple.quarantine /Applications/Alacritty.app >/dev/null 2>&1; then
    progress_step 'Removing Alacritty.app quarantine…' \
      'Alacritty.app quarantine removed' 'Alacritty.app quarantine removal failed' \
      "Remove quarantine from Alacritty.app" sudo xattr -r -d com.apple.quarantine /Applications/Alacritty.app
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
