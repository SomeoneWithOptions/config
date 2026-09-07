# Settings applied to the running machine (not files copied into place).
# Requires config/dotfiles.sh to have run first, because several of these
# act on files it installed.

current_login_shell() {
    if [[ "$OS_NAME" == "Darwin" ]]; then
        dscl . -read "/Users/$USER" UserShell 2>/dev/null | awk '{print $2}'
    else
        getent passwd "$USER" | awk -F: '{print $7}'
    fi
}

FISH_PATH=$(command -v fish || true)
if [[ -n "${FISH_PATH:-}" ]]; then
    LOGIN_SHELL=$(current_login_shell || true)
    if (( CHECK )); then
        if [[ "$LOGIN_SHELL" != "$FISH_PATH" ]]; then
            report_drift "login shell" "" "is ${LOGIN_SHELL:-unset}, repo wants $FISH_PATH"
        fi
    else
        if [[ -f /etc/shells ]] && ! grep -qxF "$FISH_PATH" /etc/shells; then
            if [[ -w /etc/shells ]]; then
                printf '%s\n' "$FISH_PATH" >> /etc/shells
            else
                printf '%s\n' "$FISH_PATH" | sudo tee -a /etc/shells >/dev/null
            fi
        fi

        if [[ "$LOGIN_SHELL" != "$FISH_PATH" ]]; then
            # Use sudo so the only allowed prompt is sudo authentication, not chsh's own password prompt.
            if command -v sudo >/dev/null 2>&1; then
                if ! sudo chsh -s "$FISH_PATH" "$USER"; then
                    report_warning 'Could not change the default shell to fish.'
                    report_action fish-shell 'Fish → change login shell' \
                      "Run (Bash): $(printf 'sudo chsh -s %q %q' "$FISH_PATH" "$USER")"
                fi
            else
                report_action fish-shell 'Fish → change login shell (sudo unavailable)' \
                  "Run (Bash): $(printf 'chsh -s %q' "$FISH_PATH")"
            fi
        fi
    fi
fi

if [[ "$OS_NAME" == "Darwin" ]]; then
    # Disable font smoothing for crisp text rendering in Alacritty.
    if [[ "$(defaults read org.alacritty AppleFontSmoothing 2>/dev/null || true)" != "0" ]]; then
        if (( CHECK )); then
            report_drift "defaults org.alacritty AppleFontSmoothing" "" "not 0"
        else
            defaults write org.alacritty AppleFontSmoothing -int 0
        fi
    fi
fi

if [[ "$OS_NAME" == "Linux" ]]; then
    if (( ! CHECK )); then
        if command -v hyprctl >/dev/null 2>&1; then
            hyprctl reload >/dev/null 2>&1 || true
            hyprctl configerrors || true
        fi
        # `omarchy restart hyprsunset` spawns a daemon that outlives this update, and
        # it inherits the update's flock fd -> the lock is held until reboot and every
        # later `omarchy update` reports one already running. Close the fd for the child.
        : "${OMARCHY_UPDATE_LOCK_FD:=9}"  # 9 is unused when we're not under the lock
        omarchy restart hyprsunset {OMARCHY_UPDATE_LOCK_FD}>&- || true
    fi

    if command -v xdg-settings >/dev/null 2>&1 && command -v zen-browser >/dev/null 2>&1; then
        # Omarchy shells export BROWSER=omarchy-launch-browser (default/bash/envs);
        # xdg-settings refuses `set` and skews `get` while BROWSER is in the env.
        if (( CHECK )); then
            browser="$(env -u BROWSER xdg-settings get default-web-browser 2>/dev/null || true)"
            [[ "$browser" == "zen.desktop" ]] || report_drift "default web browser" "" "is ${browser:-unset}, repo wants zen.desktop"
        else
            env -u BROWSER xdg-settings set default-web-browser zen.desktop || true
        fi
    fi

    current_theme="$(omarchy theme current 2>/dev/null || true)"
    if [[ "$current_theme" != "Solitude" ]]; then
        if (( CHECK )); then
            report_drift "omarchy theme" "" "is ${current_theme:-unknown}, repo wants Solitude"
        else
            omarchy theme set Solitude || true
        fi
    fi

    if (( CHECK )); then
        if [[ "$(systemctl --user is-enabled mise-go-upgrade.timer 2>/dev/null || true)" != "enabled" ]]; then
            report_drift "mise-go-upgrade.timer" "" "not enabled"
        fi
    else
        systemctl --user daemon-reload || true
        systemctl --user enable --now mise-go-upgrade.timer || true
    fi
fi
