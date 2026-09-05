#!/usr/bin/env bash

set -euo pipefail

# Usage: 4 ConfigFiles.sh [--check]
#
# Default: copy every managed config into ~ (idempotent, rerun any time).
# --check: write nothing. Print a unified diff for every managed target that
#          differs from the repo, then a count. The post-update hook runs this so
#          `omarchy update` migrations and other tools' edits are seen, not undone.

CHECK=0
case "${1:-}" in
    --check) CHECK=1 ;;
    "") ;;
    *) printf 'Usage: %s [--check]\n' "$0" >&2; exit 2 ;;
esac
DRIFT=0

OS_NAME=$(uname -s)
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib/report.sh
. "$SCRIPT_DIR/lib/report.sh"

# report_drift TARGET [SOURCE] [NOTE]
# Prints one "== TARGET: ..." header per drifted target so callers can count them.
# With SOURCE, shows what applying the repo would change (- live, + repo).
report_drift() {
    local target="$1" source="${2:-}" note="${3:-}"

    DRIFT=$((DRIFT + 1))
    if [[ -n "$note" ]]; then
        printf '\n== %s: %s\n' "$target" "$note"
    elif [[ ! -e "$target" ]]; then
        printf '\n== %s: missing (repo would create it)\n' "$target"
    elif [[ -d "$source" ]]; then
        printf '\n== %s: differs (- live, + repo)\n' "$target"
        diff -ru "$target" "$source" || true
    else
        printf '\n== %s: differs (- live, + repo)\n' "$target"
        diff -u -L live -L repo "$target" "$source" || true
    fi
}

copy_required() {
    local source_path="$1"
    local dest_path="$2"

    if [[ ! -f "$source_path" ]]; then
        printf 'Missing required config file: %s\n' "$source_path" >&2
        exit 1
    fi

    if [[ -f "$dest_path" ]] && cmp -s "$source_path" "$dest_path"; then
        return
    fi
    if (( CHECK )); then
        report_drift "$dest_path" "$source_path"
        return
    fi

    mkdir -p "$(dirname "$dest_path")"
    cp "$source_path" "$dest_path"
    printf 'Updated %s\n' "$dest_path"
}

copy_required_if_missing() {
    local source_path="$1"
    local dest_path="$2"

    if [[ ! -f "$source_path" ]]; then
        printf 'Missing required config file: %s\n' "$source_path" >&2
        exit 1
    fi

    if [[ -e "$dest_path" ]]; then
        return
    fi
    if (( CHECK )); then
        report_drift "$dest_path" "" "missing (seed file; repo would create it)"
        return
    fi

    mkdir -p "$(dirname "$dest_path")"
    cp "$source_path" "$dest_path"
    printf 'Created %s\n' "$dest_path"
}

copy_executable_required() {
    local source_path="$1"
    local dest_path="$2"

    copy_required "$source_path" "$dest_path"
    (( CHECK )) || chmod +x "$dest_path"
}

copy_dir_required() {
    local source_path="$1"
    local dest_path="$2"

    if [[ ! -d "$source_path" ]]; then
        printf 'Missing required config directory: %s\n' "$source_path" >&2
        exit 1
    fi

    # Content only: rsync's itemize also flags mtime, which differs between
    # checkouts of identical files.
    if (( CHECK )); then
        if [[ ! -d "$dest_path" ]] || ! diff -qr "$source_path" "$dest_path" >/dev/null 2>&1; then
            report_drift "$dest_path" "$source_path"
        fi
        return
    fi

    if command -v rsync >/dev/null 2>&1; then
        local changes
        mkdir -p "$(dirname "$dest_path")"
        changes=$(rsync -a --delete --itemize-changes "$source_path/" "$dest_path/")
        if [[ -n "$changes" ]]; then
            printf 'Updated %s\n' "$dest_path"
        fi
        return
    fi

    if [[ -d "$dest_path" ]] && diff -qr "$source_path" "$dest_path" >/dev/null 2>&1; then
        return
    fi
    mkdir -p "$(dirname "$dest_path")"
    rm -rf "$dest_path"
    cp -R "$source_path" "$dest_path"
    printf 'Updated %s\n' "$dest_path"
}

append_line_once() {
    local line="$1"
    local file="$2"

    if [[ -f "$file" ]] && grep -qxF "$line" "$file"; then
        return
    fi
    if (( CHECK )); then
        report_drift "$file" "" "missing line: $line"
        return
    fi
    mkdir -p "$(dirname "$file")"
    touch "$file"
    printf '%s\n' "$line" >> "$file"
}

current_login_shell() {
    if [[ "$OS_NAME" == "Darwin" ]]; then
        dscl . -read "/Users/$USER" UserShell 2>/dev/null | awk '{print $2}'
    else
        getent passwd "$USER" | awk -F: '{print $7}'
    fi
}

# Pi Configuration
(( CHECK )) || mkdir -p "$HOME/code/worktrees" # /worktree extension creates worktrees here
copy_required "$SCRIPT_DIR/pi/agent/AGENTS.md" "$HOME/.pi/agent/AGENTS.md"
for extension in "$SCRIPT_DIR"/pi/agent/extensions/*.ts; do
    copy_required "$extension" "$HOME/.pi/agent/extensions/$(basename "$extension")"
done
# Seed only: pi writes this file itself (lastChangelogVersion, model picks made in
# the TUI). Overwriting it on every update replayed the changelog and reset models.
copy_required_if_missing "$SCRIPT_DIR/pi/agent/settings.json" "$HOME/.pi/agent/settings.json"
for skill in "$SCRIPT_DIR"/pi/agent/skills/*; do
    skill_name="$(basename "$skill")"
    # a-front is user-updatable: seed it once, never overwrite local edits on replay.
    [[ "$skill_name" == "a-front" && -d "$HOME/.pi/agent/skills/a-front" ]] && continue
    copy_dir_required "$skill" "$HOME/.pi/agent/skills/$skill_name"
done

# Fish Configuration
FISH_CONFIG_SOURCE="$SCRIPT_DIR/fish/config.fish"
FISH_CONFIG_DEST="$HOME/.config/fish/config.fish"
if [[ ! -f "$FISH_CONFIG_SOURCE" ]]; then
    printf 'Missing required config file: %s\n' "$FISH_CONFIG_SOURCE" >&2
    exit 1
fi

FISH_CONFIG_TMP=$(mktemp)
cp "$FISH_CONFIG_SOURCE" "$FISH_CONFIG_TMP"
if [[ "$OS_NAME" == "Darwin" ]] && command -v brew >/dev/null 2>&1; then
    BREW_PATH=$(command -v brew)
    printf '\n' >> "$FISH_CONFIG_TMP"
    cat >> "$FISH_CONFIG_TMP" <<EOF
if test -x "$BREW_PATH"
    "$BREW_PATH" shellenv | source
end

set -l node24_prefix ("$BREW_PATH" --prefix node@24 2>/dev/null)
if test -n "\$node24_prefix"
    fish_add_path --move --path "\$node24_prefix/bin"
end
EOF
fi
if [[ ! -f "$FISH_CONFIG_DEST" ]] || ! cmp -s "$FISH_CONFIG_TMP" "$FISH_CONFIG_DEST"; then
    if (( CHECK )); then
        report_drift "$FISH_CONFIG_DEST" "$FISH_CONFIG_TMP"
    else
        mkdir -p "$(dirname "$FISH_CONFIG_DEST")"
        cp "$FISH_CONFIG_TMP" "$FISH_CONFIG_DEST"
        printf 'Updated %s\n' "$FISH_CONFIG_DEST"
    fi
fi
rm -f "$FISH_CONFIG_TMP"

copy_required "$SCRIPT_DIR/fish/conf.d/theme.fish" "$HOME/.config/fish/conf.d/theme.fish"
copy_required "$SCRIPT_DIR/fish/conf.d/key_bindings.fish" "$HOME/.config/fish/conf.d/key_bindings.fish"
copy_required "$SCRIPT_DIR/fish/conf.d/turso.fish" "$HOME/.config/fish/conf.d/turso.fish"
copy_required "$SCRIPT_DIR/fish/functions/fish_prompt.fish" "$HOME/.config/fish/functions/fish_prompt.fish"
copy_required "$SCRIPT_DIR/fish/functions/dian.fish" "$HOME/.config/fish/functions/dian.fish"

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

# Fontconfig / GTK Configuration
copy_required "$SCRIPT_DIR/fontconfig/fonts.conf" "$HOME/.config/fontconfig/fonts.conf"
copy_required "$SCRIPT_DIR/gtk-3.0/settings.ini" "$HOME/.config/gtk-3.0/settings.ini"
copy_required "$SCRIPT_DIR/gtk-4.0/settings.ini" "$HOME/.config/gtk-4.0/settings.ini"
copy_required "$SCRIPT_DIR/git/ignore" "$HOME/.config/git/ignore"

# Alacritty Configuration
copy_required "$SCRIPT_DIR/alacritty/alacritty.toml" "$HOME/.config/alacritty/alacritty.toml"

# Ghostty Configuration
copy_required "$SCRIPT_DIR/ghostty/config" "$HOME/.config/ghostty/config"

# Foot Configuration (default terminal on Linux; see xdg-terminals.list below)
copy_required "$SCRIPT_DIR/foot/foot.ini" "$HOME/.config/foot/foot.ini"

# Zed Configuration
copy_required "$SCRIPT_DIR/zed/settings.json" "$HOME/.config/zed/settings.json"
copy_required "$SCRIPT_DIR/zed/keymap.json" "$HOME/.config/zed/keymap.json"

# macOS Configuration
if [[ "$OS_NAME" == "Darwin" ]]; then
    copy_required "$SCRIPT_DIR/aerospace/aerospace.toml" "$HOME/.config/aerospace/aerospace.toml"

    # Disable font smoothing for crisp text rendering in Alacritty.
    if [[ "$(defaults read org.alacritty AppleFontSmoothing 2>/dev/null || true)" != "0" ]]; then
        if (( CHECK )); then
            report_drift "defaults org.alacritty AppleFontSmoothing" "" "not 0"
        else
            defaults write org.alacritty AppleFontSmoothing -int 0
        fi
    fi

    # macOS only: on Linux, Omarchy's install/user/mise.sh generates byte-identical
    # wrappers for these two via omarchy-mise-install.
    for helper in ghui hunk; do
        copy_executable_required "$SCRIPT_DIR/bin/$helper" "$HOME/.local/bin/$helper"
    done
fi

# Vim Configuration
VIMRC="$HOME/.vimrc"
append_line_once "set number" "$VIMRC"
append_line_once "set relativenumber" "$VIMRC"

# Omarchy/Arch Configuration (the only Linux this repo configures)
if [[ "$OS_NAME" == "Linux" ]]; then
    # Hyprland
    for hypr_file in "$SCRIPT_DIR"/hypr/*; do
        copy_required "$hypr_file" "$HOME/.config/hypr/$(basename "$hypr_file")"
    done

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

    # Hyprland/Omarchy helper scripts.
    for helper in "$SCRIPT_DIR"/bin/*; do
        helper_name="$(basename "$helper")"
        # ghui/hunk are macOS-only here (Omarchy generates them on Linux); flicko-slurp
        # goes to a scoped dir below.
        [[ "$helper_name" == ghui || "$helper_name" == hunk || "$helper_name" == flicko-slurp ]] && continue
        copy_executable_required "$helper" "$HOME/.local/bin/$helper_name"
    done

    # Animated screenshot selector. Adapter is named `slurp` only inside the
    # screenshot wrapper's scoped PATH, leaving the system slurp untouched.
    copy_required "$SCRIPT_DIR/quickshell/flicko-picker/shell.qml" "$HOME/.config/quickshell/flicko-picker/shell.qml"
    copy_executable_required "$SCRIPT_DIR/bin/flicko-slurp" "$HOME/.local/lib/flicko-picker/slurp"
    # Optional fixed picker accent. Absent here, a machine-local color file is
    # left alone; absent in both, the picker follows the theme accent.
    if [[ -f "$SCRIPT_DIR/quickshell/flicko-picker/color" ]]; then
        copy_required "$SCRIPT_DIR/quickshell/flicko-picker/color" "$HOME/.config/quickshell/flicko-picker/color"
    fi

    for plugin in "$SCRIPT_DIR"/omarchy/plugins/andres.*; do
        copy_dir_required "$plugin" "$HOME/.config/omarchy/plugins/$(basename "$plugin")"
    done
    copy_required "$SCRIPT_DIR/omarchy/extensions/omarchy-menu.jsonc" "$HOME/.config/omarchy/extensions/omarchy-menu.jsonc"
    framed_panels_changed=""
    if (( CHECK )); then
        # Generate into a scratch root and diff against the live plugins.
        framed_panels_tmp="$(mktemp -d)"
        if OMARCHY_CONFIG_ROOT="$framed_panels_tmp" python "$SCRIPT_DIR/omarchy/install-framed-panels.py" >/dev/null 2>&1; then
            for generated in "$framed_panels_tmp"/plugins/andres.*; do
                live="$HOME/.config/omarchy/plugins/$(basename "$generated")"
                if [[ ! -d "$live" ]] || ! diff -qr "$generated" "$live" >/dev/null 2>&1; then
                    report_drift "$live" "$generated"
                fi
            done
        else
            report_drift "framed panels" "" "generation FAILED (upstream panel source changed)"
        fi
        rm -rf "$framed_panels_tmp"
    elif ! framed_panels_changed=$(python "$SCRIPT_DIR/omarchy/install-framed-panels.py"); then
        report_warning 'Framed panel generation FAILED (upstream panel source changed).'
        if command -v notify-send >/dev/null 2>&1; then
            notify-send -u critical "Config replay" "Framed panels failed to regenerate" || true
        fi
        framed_panels_changed=""
    fi
    copy_required "$SCRIPT_DIR/omarchy/shell.json" "$HOME/.config/omarchy/shell.json"
    copy_required "$SCRIPT_DIR/omarchy/shell.toml" "$HOME/.config/omarchy/shell.toml"
    if (( ! CHECK )); then
        if [[ -n "$framed_panels_changed" ]]; then
            printf 'Updated framed Omarchy panels\n'
            omarchy restart shell || true
        else
            omarchy-shell shell rescanPlugins >/dev/null 2>&1 || true
        fi
    fi

    # XDG defaults
    copy_required "$SCRIPT_DIR/xdg/xdg-terminals.list" "$HOME/.config/xdg-terminals.list"
    # Seed only: apps append their own associations here (xdg-mime, browser
    # "set as default" buttons). A plain copy reverted those on every update.
    copy_required_if_missing "$SCRIPT_DIR/xdg/mimeapps.list" "$HOME/.config/mimeapps.list"
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

    # Zen prefs + chrome CSS. The CSS hides native window controls and assumes the
    # Omarchy/Hyprland shell. Profile dirs are randomly named, so fan out over all
    # of them. Zen only creates a profile on first launch: if none exists yet,
    # launch Zen once and re-run this script.
    zen_profiles_found=0
    for zen_profile in "$HOME"/.config/zen/*/; do
        [[ -f "$zen_profile/times.json" || -f "$zen_profile/prefs.js" ]] || continue
        copy_required "$SCRIPT_DIR/zen/user.js" "$zen_profile/user.js"
        copy_required "$SCRIPT_DIR/zen/userChrome.css" "$zen_profile/chrome/userChrome.css"
        zen_profiles_found=1
    done
    if [[ $zen_profiles_found -eq 0 ]]; then
        if (( CHECK )); then
            printf 'No Zen profile yet: launch Zen once, then re-run this script.\n'
        else
            report_action zen 'Zen → create browser profile' \
              'Launch Zen once, then close it.' \
              "Rerun (Bash): $(printf 'bash %q' "$SCRIPT_DIR/4 ConfigFiles.sh")"
        fi
    fi

    # Omarchy theme, branding, and hooks
    copy_required "$SCRIPT_DIR/omarchy/branding/about.txt" "$HOME/.config/omarchy/branding/about.txt"
    copy_required "$SCRIPT_DIR/omarchy/branding/screensaver.txt" "$HOME/.config/omarchy/branding/screensaver.txt"
    for hook_dir in "$SCRIPT_DIR"/omarchy/hooks/*.d; do
        event="$(basename "$hook_dir")"
        for hook in "$hook_dir"/*; do
            copy_executable_required "$hook" "$HOME/.config/omarchy/hooks/$event/$(basename "$hook")"
        done
    done
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

    current_theme="$(omarchy theme current 2>/dev/null || true)"
    if [[ "$current_theme" != "Solitude" ]]; then
        if (( CHECK )); then
            report_drift "omarchy theme" "" "is ${current_theme:-unknown}, repo wants Solitude"
        else
            omarchy theme set Solitude || true
        fi
    fi

    # Custom user systemd units/timers
    for unit in "$SCRIPT_DIR"/systemd/user/*; do
        copy_required "$unit" "$HOME/.config/systemd/user/$(basename "$unit")"
    done
    if (( CHECK )); then
        if [[ "$(systemctl --user is-enabled mise-go-upgrade.timer 2>/dev/null || true)" != "enabled" ]]; then
            report_drift "mise-go-upgrade.timer" "" "not enabled"
        fi
    else
        systemctl --user daemon-reload || true
        systemctl --user enable --now mise-go-upgrade.timer || true
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

if (( CHECK )); then
    if (( DRIFT == 0 )); then
        printf 'No drift: every managed target matches the repo.\n'
    else
        printf '\n%d managed target(s) differ from the repo.\n' "$DRIFT"
        printf 'Apply repo state: bash "%s"   Or port the live changes into the repo.\n' "$SCRIPT_DIR/4 ConfigFiles.sh"
    fi
fi
