# macOS/Homebrew package install.

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
  install_turso
}
