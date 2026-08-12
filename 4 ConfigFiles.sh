#!/usr/bin/env bash

set -euo pipefail

OS_NAME=$(uname -s)
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

copy_required() {
    local source_path="$1"
    local dest_path="$2"

    if [[ ! -f "$source_path" ]]; then
        printf 'Missing required config file: %s\n' "$source_path" >&2
        exit 1
    fi

    mkdir -p "$(dirname "$dest_path")"
    if [[ ! -f "$dest_path" ]] || ! cmp -s "$source_path" "$dest_path"; then
        cp "$source_path" "$dest_path"
        printf 'Updated %s\n' "$dest_path"
    fi
}

copy_required_if_missing() {
    local source_path="$1"
    local dest_path="$2"

    if [[ ! -f "$source_path" ]]; then
        printf 'Missing required config file: %s\n' "$source_path" >&2
        exit 1
    fi

    mkdir -p "$(dirname "$dest_path")"
    if [[ ! -e "$dest_path" ]]; then
        cp "$source_path" "$dest_path"
        printf 'Created %s\n' "$dest_path"
    fi
}

copy_executable_required() {
    local source_path="$1"
    local dest_path="$2"

    copy_required "$source_path" "$dest_path"
    chmod +x "$dest_path"
}

copy_dir_required() {
    local source_path="$1"
    local dest_path="$2"

    if [[ ! -d "$source_path" ]]; then
        printf 'Missing required config directory: %s\n' "$source_path" >&2
        exit 1
    fi

    mkdir -p "$(dirname "$dest_path")"
    if command -v rsync >/dev/null 2>&1; then
        local changes
        changes=$(rsync -a --delete --itemize-changes "$source_path/" "$dest_path/")
        if [[ -n "$changes" ]]; then
            printf 'Updated %s\n' "$dest_path"
        fi
        return
    fi

    if [[ ! -d "$dest_path" ]] || ! diff -qr "$source_path" "$dest_path" >/dev/null 2>&1; then
        rm -rf "$dest_path"
        cp -R "$source_path" "$dest_path"
        printf 'Updated %s\n' "$dest_path"
    fi
}

append_line_once() {
    local line="$1"
    local file="$2"

    mkdir -p "$(dirname "$file")"
    touch "$file"
    if ! grep -qxF "$line" "$file"; then
        printf '%s\n' "$line" >> "$file"
    fi
}

current_login_shell() {
    if command -v getent >/dev/null 2>&1; then
        getent passwd "$USER" | awk -F: '{print $7}'
        return
    fi

    if [[ "$OS_NAME" == "Darwin" ]] && command -v dscl >/dev/null 2>&1; then
        dscl . -read "/Users/$USER" UserShell 2>/dev/null | awk '{print $2}'
        return
    fi

    printf '%s\n' "${SHELL:-}"
}

is_arch_like() {
    if [[ ! -f /etc/os-release ]]; then
        return 1
    fi

    # shellcheck disable=SC1091
    . /etc/os-release
    [[ "${ID:-}" == "arch" || "${ID_LIKE:-}" == *"arch"* ]]
}

user_systemctl() {
    if command -v systemctl >/dev/null 2>&1; then
        systemctl --user "$@" || true
    fi
}

restart_if_present() {
    local command_name="$1"

    if command -v "$command_name" >/dev/null 2>&1; then
        "$command_name" || true
    fi
}

# Pi Configuration
mkdir -p "$HOME/.pi/agent/extensions"
mkdir -p "$HOME/.pi/agent/skills"
mkdir -p "$HOME/code/worktrees" # /worktree extension creates worktrees here
copy_required "$SCRIPT_DIR/pi/agent/AGENTS.md" "$HOME/.pi/agent/AGENTS.md"
copy_required "$SCRIPT_DIR/pi/agent/extensions/rtk-bash-rewrite.ts" "$HOME/.pi/agent/extensions/rtk-bash-rewrite.ts"
copy_required "$SCRIPT_DIR/pi/agent/extensions/ask-user.ts" "$HOME/.pi/agent/extensions/ask-user.ts"
copy_required "$SCRIPT_DIR/pi/agent/extensions/exit-command.ts" "$HOME/.pi/agent/extensions/exit-command.ts"
copy_required "$SCRIPT_DIR/pi/agent/extensions/web-research.ts" "$HOME/.pi/agent/extensions/web-research.ts"
copy_required "$SCRIPT_DIR/pi/agent/extensions/omarchy-system-theme.ts" "$HOME/.pi/agent/extensions/omarchy-system-theme.ts"
copy_required "$SCRIPT_DIR/pi/agent/extensions/worktree.ts" "$HOME/.pi/agent/extensions/worktree.ts"
copy_required "$SCRIPT_DIR/pi/agent/settings.json" "$HOME/.pi/agent/settings.json"
copy_dir_required "$SCRIPT_DIR/pi/agent/skills/a-front" "$HOME/.pi/agent/skills/a-front"
copy_dir_required "$SCRIPT_DIR/pi/agent/skills/caveman" "$HOME/.pi/agent/skills/caveman"
copy_dir_required "$SCRIPT_DIR/pi/agent/skills/o-front" "$HOME/.pi/agent/skills/o-front"
copy_dir_required "$SCRIPT_DIR/pi/agent/skills/grill-me" "$HOME/.pi/agent/skills/grill-me"
copy_dir_required "$SCRIPT_DIR/pi/agent/skills/impeccable" "$HOME/.pi/agent/skills/impeccable"

# Local Helper Scripts
mkdir -p "$HOME/.local/bin"
for helper in \
    alt-edit-shortcut \
    battery-power-mode \
    copy-file-to-clipboard \
    hyprsunset-gamma-display \
    lid-monitor-mode \
    lid-monitor-mode-watch \
    matrix-launch-screensaver \
    matrix-screensaver \
    omarchy-frame \
    omarchy-screenshot-file-clipboard; do
    copy_executable_required "$SCRIPT_DIR/bin/$helper" "$HOME/.local/bin/$helper"
done

# Fish Configuration
mkdir -p "$HOME/.config/fish"
mkdir -p "$HOME/.config/fish/conf.d"
mkdir -p "$HOME/.config/fish/functions"
mkdir -p "$HOME/.local/share/fish"

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
mkdir -p "$(dirname "$FISH_CONFIG_DEST")"
if [[ ! -f "$FISH_CONFIG_DEST" ]] || ! cmp -s "$FISH_CONFIG_TMP" "$FISH_CONFIG_DEST"; then
    cp "$FISH_CONFIG_TMP" "$FISH_CONFIG_DEST"
    printf 'Updated %s\n' "$FISH_CONFIG_DEST"
fi
rm -f "$FISH_CONFIG_TMP"

copy_required "$SCRIPT_DIR/fish/conf.d/theme.fish" "$HOME/.config/fish/conf.d/theme.fish"
copy_required "$SCRIPT_DIR/fish/conf.d/key_bindings.fish" "$HOME/.config/fish/conf.d/key_bindings.fish"
copy_required "$SCRIPT_DIR/fish/functions/fish_prompt.fish" "$HOME/.config/fish/functions/fish_prompt.fish"
copy_required "$SCRIPT_DIR/fish/functions/dian.fish" "$HOME/.config/fish/functions/dian.fish"
if [[ -f "$SCRIPT_DIR/fish/fish_history" ]]; then
    copy_required_if_missing "$SCRIPT_DIR/fish/fish_history" "$HOME/.local/share/fish/fish_history"
fi

FISH_PATH=$(command -v fish || true)
if [[ -n "${FISH_PATH:-}" ]]; then
    if [[ -f /etc/shells ]] && ! grep -qxF "$FISH_PATH" /etc/shells; then
        if [[ -w /etc/shells ]]; then
            printf '%s\n' "$FISH_PATH" >> /etc/shells
        else
            printf '%s\n' "$FISH_PATH" | sudo tee -a /etc/shells >/dev/null
        fi
    fi

    LOGIN_SHELL=$(current_login_shell || true)
    if [[ "$LOGIN_SHELL" != "$FISH_PATH" ]]; then
        # Use sudo so the only allowed prompt is sudo authentication, not chsh's own password prompt.
        if command -v sudo >/dev/null 2>&1; then
            if ! sudo chsh -s "$FISH_PATH" "$USER"; then
                printf 'Failed to change the default shell to fish. You may need to rerun `sudo chsh -s %s %s` manually.\n' "$FISH_PATH" "$USER" >&2
            fi
        else
            printf 'sudo not found; skipping default shell change. Run `chsh -s %s` manually if desired.\n' "$FISH_PATH" >&2
        fi
    fi
fi

# Fontconfig / GTK / Mise Configuration
copy_required "$SCRIPT_DIR/fontconfig/fonts.conf" "$HOME/.config/fontconfig/fonts.conf"
copy_required "$SCRIPT_DIR/gtk-3.0/settings.ini" "$HOME/.config/gtk-3.0/settings.ini"
copy_required "$SCRIPT_DIR/gtk-4.0/settings.ini" "$HOME/.config/gtk-4.0/settings.ini"
copy_required "$SCRIPT_DIR/mise/config.toml" "$HOME/.config/mise/config.toml"
copy_required "$SCRIPT_DIR/git/ignore" "$HOME/.config/git/ignore"

# Alacritty Configuration
mkdir -p "$HOME/.config/alacritty"
copy_required "$SCRIPT_DIR/alacritty/alacritty.toml" "$HOME/.config/alacritty/alacritty.toml"

# Disable font smoothing for crisp text rendering (macOS only)
if [[ "$OS_NAME" == "Darwin" ]]; then
    current_smoothing=$(defaults read org.alacritty AppleFontSmoothing 2>/dev/null || true)
    if [[ "$current_smoothing" != "0" ]]; then
        defaults write org.alacritty AppleFontSmoothing -int 0
    fi
fi

# Ghostty Configuration
copy_required "$SCRIPT_DIR/ghostty/config" "$HOME/.config/ghostty/config"

# Tmux Configuration
TMUX_CONF="$HOME/.tmux.conf"
touch "$TMUX_CONF"
append_line_once "set -g mouse on" "$TMUX_CONF"
append_line_once "set -g base-index 1" "$TMUX_CONF"

# Zed Configuration
mkdir -p "$HOME/.config/zed"
copy_required "$SCRIPT_DIR/zed/settings.json" "$HOME/.config/zed/settings.json"
copy_required "$SCRIPT_DIR/zed/keymap.json" "$HOME/.config/zed/keymap.json"

# AeroSpace Configuration (macOS only)
if [[ "$OS_NAME" == "Darwin" ]]; then
    mkdir -p "$HOME/.config/aerospace"
    copy_required "$SCRIPT_DIR/aerospace/aerospace.toml" "$HOME/.config/aerospace/aerospace.toml"
fi

# Vim Configuration
VIMRC="$HOME/.vimrc"
touch "$VIMRC"
append_line_once "set number" "$VIMRC"
append_line_once "set relativenumber" "$VIMRC"

# Neovim Configuration
copy_dir_required "$SCRIPT_DIR/nvim" "$HOME/.config/nvim"

# Hyprland Configuration
if [[ "$OS_NAME" == "Linux" ]]; then
    mkdir -p "$HOME/.config/hypr"
    for hypr_file in \
        autostart.conf \
        bindings.conf \
        hypridle.conf \
        hyprland.conf \
        hyprlock.conf \
        hyprsunset.conf \
        input.conf \
        looknfeel.conf \
        monitors.conf \
        xdph.conf; do
        copy_required "$SCRIPT_DIR/hypr/$hypr_file" "$HOME/.config/hypr/$hypr_file"
    done

    # hyprland.conf sources this, so it must exist before the reload below.
    # `omarchy-frame` owns it afterwards -- copying it every run would clobber
    # the machine-local on/off state.
    copy_required_if_missing "$SCRIPT_DIR/hypr/desktop-frame.conf" "$HOME/.config/hypr/desktop-frame.conf"

    if command -v hyprctl >/dev/null 2>&1; then
        hyprctl reload >/dev/null 2>&1 || true
        hyprctl configerrors || true
    fi
    restart_if_present omarchy-restart-hypridle
    restart_if_present omarchy-restart-hyprsunset
fi

# Arch/Omarchy Specific Configuration
if is_arch_like; then
    # Animated screenshot selector. Adapter is named `slurp` only inside the
    # screenshot wrapper's scoped PATH, leaving the system slurp untouched.
    copy_required "$SCRIPT_DIR/quickshell/flicko-picker/shell.qml" "$HOME/.config/quickshell/flicko-picker/shell.qml"
    copy_executable_required "$SCRIPT_DIR/bin/flicko-slurp" "$HOME/.local/lib/flicko-picker/slurp"

    # Standalone today; same manifest/components load as a Quattro plugin later.
    copy_dir_required "$SCRIPT_DIR/quickshell/desktop-frame" "$HOME/.config/quickshell/desktop-frame"
    copy_dir_required "$SCRIPT_DIR/quickshell/desktop-frame" "$HOME/.config/omarchy/plugins/andres.desktop-frame"
    "$HOME/.local/bin/omarchy-frame" configure

    # XDG defaults
    copy_required "$SCRIPT_DIR/xdg/xdg-terminals.list" "$HOME/.config/xdg-terminals.list"
    copy_required "$SCRIPT_DIR/xdg/mimeapps.list" "$HOME/.config/mimeapps.list"
    if command -v xdg-settings >/dev/null 2>&1 && command -v zen-browser >/dev/null 2>&1; then
        xdg-settings set default-web-browser zen.desktop || true
    fi

    # Zen prefs + chrome CSS. Omarchy laptops only: the CSS hides native window
    # controls and assumes the Omarchy/Hyprland shell, so it is wrong elsewhere.
    # Profile dirs are randomly named, so fan out over all of them. Zen only
    # creates a profile on first launch: if none exists yet, launch Zen once and
    # re-run this script.
    if command -v omarchy >/dev/null 2>&1; then
        zen_profiles_found=0
        for zen_profile in "$HOME"/.config/zen/*/; do
            [[ -f "$zen_profile/times.json" || -f "$zen_profile/prefs.js" ]] || continue
            copy_required "$SCRIPT_DIR/zen/user.js" "$zen_profile/user.js"
            copy_required "$SCRIPT_DIR/zen/userChrome.css" "$zen_profile/chrome/userChrome.css"
            zen_profiles_found=1
        done
        if [[ $zen_profiles_found -eq 0 ]]; then
            printf 'No Zen profile yet: launch Zen once, then re-run this script.\n'
        fi
    fi

    # Waybar exact snapshot. It is the fallback bar for `omarchy-frame off`, so
    # the config is still installed, but restarting it while the frame owns the
    # top bar would stack two bars. `omarchy-frame configure` above owns the flag.
    copy_dir_required "$SCRIPT_DIR/waybar" "$HOME/.config/waybar"
    if [[ ! -e "${XDG_STATE_HOME:-$HOME/.local/state}/omarchy/toggles/waybar-off" ]]; then
        restart_if_present omarchy-restart-waybar
    fi

    # SwayOSD styling
    copy_required "$SCRIPT_DIR/swayosd/style.css" "$HOME/.config/swayosd/style.css"
    restart_if_present omarchy-restart-swayosd

    # Walker exact snapshot
    mkdir -p "$HOME/.config/walker/themes"
    copy_required "$SCRIPT_DIR/walker/config.toml" "$HOME/.config/walker/config.toml"
    copy_dir_required "$SCRIPT_DIR/walker/themes/frame" "$HOME/.config/walker/themes/frame"
    restart_if_present omarchy-restart-walker

    # Omarchy theme, branding, background, and hooks
    mkdir -p "$HOME/.config/omarchy/branding"
    mkdir -p "$HOME/.config/omarchy/backgrounds"
    mkdir -p "$HOME/.config/omarchy/hooks/post-update.d"
    mkdir -p "$HOME/.config/omarchy/hooks/theme-set.d"
    copy_required "$SCRIPT_DIR/omarchy/branding/about.txt" "$HOME/.config/omarchy/branding/about.txt"
    copy_required "$SCRIPT_DIR/omarchy/branding/screensaver.txt" "$HOME/.config/omarchy/branding/screensaver.txt"
    copy_required "$SCRIPT_DIR/chess.jpg" "$HOME/.config/omarchy/backgrounds/chess.jpg"
    copy_executable_required "$SCRIPT_DIR/omarchy/hooks/post-update.d/update-go-with-mise" "$HOME/.config/omarchy/hooks/post-update.d/update-go-with-mise"
    copy_executable_required "$SCRIPT_DIR/omarchy/hooks/post-update.d/reapply-user-config" "$HOME/.config/omarchy/hooks/post-update.d/reapply-user-config"
    copy_executable_required "$SCRIPT_DIR/omarchy/hooks/theme-set.d/only-chess-wallpaper" "$HOME/.config/omarchy/hooks/theme-set.d/only-chess-wallpaper"

    # The hook above reapplies this repo after `omarchy update` runs its migrations,
    # so it needs a checkout that outlives the update. `bootstrap.sh` deliberately
    # runs from a throwaway /tmp extract, so on a new laptop there is nothing at
    # CONFIG_REPO and the hook would skip silently -- exactly the failure it exists
    # to prevent. Clone over HTTPS: `5 Keys.sh` installs SSH keys only afterwards.
    CONFIG_REPO="$HOME/code/config"
    if [[ "$SCRIPT_DIR" != "$CONFIG_REPO" && ! -d "$CONFIG_REPO" ]]; then
        if command -v git >/dev/null 2>&1; then
            mkdir -p "$(dirname "$CONFIG_REPO")"
            if git clone https://github.com/SomeoneWithOptions/config.git "$CONFIG_REPO"; then
                git -C "$CONFIG_REPO" remote set-url --push origin git@github.com:SomeoneWithOptions/config.git
                printf 'Cloned config repo to %s for post-update reapply\n' "$CONFIG_REPO"
            else
                printf 'Could not clone config repo to %s; post-update reapply will skip.\n' "$CONFIG_REPO" >&2
            fi
        else
            printf 'git not found; skipped config repo clone to %s.\n' "$CONFIG_REPO" >&2
        fi
    fi

    if command -v omarchy-theme-current >/dev/null 2>&1; then
        CURRENT_THEME=$(omarchy-theme-current 2>/dev/null || true)
        if [[ "$CURRENT_THEME" != "Catppuccin" && "$CURRENT_THEME" != "catppuccin" ]]; then
            if command -v omarchy >/dev/null 2>&1; then
                omarchy theme set Catppuccin || true
            elif command -v omarchy-theme-set >/dev/null 2>&1; then
                omarchy-theme-set catppuccin || true
            fi
        fi
    fi

    mkdir -p "$HOME/.config/omarchy/current/theme"
    copy_required "$SCRIPT_DIR/omarchy/current/theme/mako.ini" "$HOME/.config/omarchy/current/theme/mako.ini"
    "$HOME/.config/omarchy/hooks/theme-set.d/only-chess-wallpaper" catppuccin || true
    # mako is stopped while the desktop frame owns notifications; reloading it
    # then just prints a DBus error. The theme file above is still its fallback.
    if pgrep -x mako >/dev/null 2>&1; then
        restart_if_present omarchy-restart-mako
    fi

    # Custom user systemd units/timers
    mkdir -p "$HOME/.config/systemd/user"
    copy_required "$SCRIPT_DIR/systemd/user/battery-power-mode.service" "$HOME/.config/systemd/user/battery-power-mode.service"
    copy_required "$SCRIPT_DIR/systemd/user/battery-power-mode.timer" "$HOME/.config/systemd/user/battery-power-mode.timer"
    copy_required "$SCRIPT_DIR/systemd/user/mise-go-upgrade.service" "$HOME/.config/systemd/user/mise-go-upgrade.service"
    copy_required "$SCRIPT_DIR/systemd/user/mise-go-upgrade.timer" "$HOME/.config/systemd/user/mise-go-upgrade.timer"
    user_systemctl daemon-reload
    user_systemctl enable --now battery-power-mode.timer
    user_systemctl enable --now mise-go-upgrade.timer
fi
