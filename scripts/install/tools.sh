# Third-party tool installers used on both platforms.
# Requires lib/report.sh, lib/common.sh and lib/pkg.sh sourced first.

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
  install_npm_cli clerk clerk
}

install_turso() {
  # Auth (`turso auth login`) is deliberately a manual follow-up below.
  #
  # Arch uses the AUR prebuilt binary: `turso-cli` builds from Go source, and
  # the dev-env Go install only happens later in install_arch_packages. The
  # upstream get.tur.so installer mutates shell rc files to add ~/.turso to
  # PATH, which this repo's dotfiles would rather own themselves.
  if [ "$(uname -s)" = "Linux" ]; then
    arch_install_if_missing turso-cli-bin
  elif brew list --formula turso >/dev/null 2>&1; then
    log "turso is already installed."
    report_software_progress skip 'turso already installed'
  elif has_command brew; then
    progress_step 'Installing turso…' 'turso installed' 'turso installation failed' \
      "Homebrew install turso" brew install tursodatabase/tap/turso
  else
    warn "brew not found; cannot install turso."
    report_software_progress fail 'turso not installed'
  fi

  # `turso whoami` exits non-zero while signed out, so only then is a login
  # left for later. Local development works without an account.
  if has_command turso && ! turso whoami >/dev/null 2>&1; then
    note turso 'Turso CLI → sign in' \
      'Run: turso auth login'
  fi
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
