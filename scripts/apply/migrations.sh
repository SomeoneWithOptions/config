# One-time cleanups for artifacts this repo used to install, plus the
# checkout the post-update drift hook needs.

if [[ "$OS_NAME" == "Linux" ]]; then
    # Retired: the old post-update hook replayed this whole script over ~/.config,
    # undoing migration edits and other tools' installs. report-config-drift
    # replaced it. Drop it from machines that still have it.
    RETIRED_HOOK="$HOME/.config/omarchy/hooks/post-update.d/reapply-user-config"
    if [[ -e "$RETIRED_HOOK" ]]; then
        if (( CHECK )); then
            report_drift "$RETIRED_HOOK" "" "retired hook still installed (repo would remove it)"
        else
            rm -f "$RETIRED_HOOK"
            printf 'Removed retired hook %s\n' "$RETIRED_HOOK"
        fi
    fi

    # The drift hook above compares ~/.config against this repo after `omarchy
    # update`, so it needs a checkout that outlives the update. `bootstrap.sh`
    # deliberately runs from a throwaway /tmp extract, so on a new laptop there is
    # nothing at CONFIG_REPO and the hook would fail loudly on the first update.
    # Clone over HTTPS: `5 Keys.sh` installs SSH keys only afterwards.
    CONFIG_REPO="$HOME/code/config"
    if [[ "$SCRIPT_DIR" != "$CONFIG_REPO" && ! -d "$CONFIG_REPO" ]]; then
        if (( CHECK )); then
            report_drift "$CONFIG_REPO" "" "missing (repo would clone it for the post-update drift check)"
        elif command -v git >/dev/null 2>&1; then
            mkdir -p "$(dirname "$CONFIG_REPO")"
            if git clone https://github.com/SomeoneWithOptions/config.git "$CONFIG_REPO"; then
                git -C "$CONFIG_REPO" remote set-url --push origin git@github.com:SomeoneWithOptions/config.git
                printf 'Cloned config repo to %s for the post-update drift check\n' "$CONFIG_REPO"
            else
                report_warning "Could not clone config repo to $CONFIG_REPO; post-update drift check will fail."
                report_action config-checkout 'Config repository → enable drift checks' \
                  "Required checkout: $CONFIG_REPO" \
                  "Rerun (Bash): $(printf 'bash %q' "$SCRIPT_DIR/4 ConfigFiles.sh")"
            fi
        else
            report_warning "git not found; skipped config repo clone to $CONFIG_REPO."
            report_action config-checkout 'Config repository → enable drift checks' \
              'Install git first.' "Required checkout: $CONFIG_REPO" \
              "Rerun (Bash): $(printf 'bash %q' "$SCRIPT_DIR/4 ConfigFiles.sh")"
        fi
    fi

    # Retired: the background rotated every 4h. Drop it from machines that still have it.
    if [[ -f "$HOME/.config/systemd/user/omarchy-bg-random.timer" ]]; then
        if (( CHECK )); then
            report_drift "$HOME/.config/systemd/user/omarchy-bg-random.timer" "" "retired timer still installed (repo would remove it)"
        else
            systemctl --user disable --now omarchy-bg-random.timer || true
            rm -f "$HOME/.config/systemd/user/omarchy-bg-random.timer" \
                  "$HOME/.config/systemd/user/omarchy-bg-random.service"
            systemctl --user daemon-reload || true
        fi
    fi
fi
