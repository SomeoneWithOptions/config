# Arch/Omarchy package and service install.

# `omarchy default editor` ends in a desktop notification and returns the toast's
# exit status. Right after an `omarchy update` restarts the shell, the notification
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

install_arch_packages() {
  # No `omarchy update` here: it stops to ask whether to remove packages and
  # waits for an answer, so it cannot run unattended. Run it by hand *before*
  # this configuration: nothing here syncs the pacman database, so the installs
  # below resolve against whatever the image shipped.
  note system-update 'Omarchy update → run it yourself' \
    'Bootstrap never updates the system: `omarchy update` asks before removing packages.' \
    'Run it before the next bootstrap, so package installs see fresh repos.' \
    'Run: omarchy update'

  remove_stock_omarchy_apps

  log "Ensuring packages are installed with pacman/yay."
  local package
  # Omarchy's own base/hardware installs already cover git, tmux, quickshell(-git)
  # and vulkan-{intel,radeon,asahi} for the detected GPU; curl/gnupg/openssh arrive
  # as dependencies. Listing them here was a no-op.
  #
  # herdr is in omarchy-base.packages. Keep it listed so a machine that lost
  # the package (or a not-yet-migrated install) still gets it; skip if present.
  #
  # libfprint here is `libfprint`, never `libfprint-git`: the AUR build
  # provides+conflicts libfprint, so `pacman -S --noconfirm` answers the conflict
  # prompt N and aborts the whole step -- and it is a downgrade besides.
  for package in \
    fish \
    alacritty \
    ghostty \
    herdr \
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
  install_turso
  install_loom_omarchy_linux
  install_linear_omarchy_plugin

  # Individual optional install failures are warnings. Only failed system update
  # returns non-zero, above, because continuing package work would be unsafe.
  return 0
}
