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

# Pi Configuration
mkdir -p "$HOME/.pi/agent/extensions"
mkdir -p "$HOME/.pi/agent/skills"
copy_required "$SCRIPT_DIR/pi/agent/AGENTS.md" "$HOME/.pi/agent/AGENTS.md"
copy_required "$SCRIPT_DIR/pi/agent/extensions/rtk-bash-rewrite.ts" "$HOME/.pi/agent/extensions/rtk-bash-rewrite.ts"
copy_required "$SCRIPT_DIR/pi/agent/extensions/ask-user.ts" "$HOME/.pi/agent/extensions/ask-user.ts"
copy_dir_required "$SCRIPT_DIR/pi/agent/skills/a-front" "$HOME/.pi/agent/skills/a-front"
copy_dir_required "$SCRIPT_DIR/pi/agent/skills/caveman" "$HOME/.pi/agent/skills/caveman"
copy_dir_required "$SCRIPT_DIR/pi/agent/skills/o-front" "$HOME/.pi/agent/skills/o-front"

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
    BREW_EVAL=$(printf 'eval "$(%s shellenv)"' "$BREW_PATH")
    if ! grep -qxF "$BREW_EVAL" "$FISH_CONFIG_TMP"; then
        printf '%s\n' "$BREW_EVAL" >> "$FISH_CONFIG_TMP"
    fi
    cat >> "$FISH_CONFIG_TMP" <<EOF
set -l node24_prefix ($BREW_PATH --prefix node@24 2>/dev/null)
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

# Hyprland Configuration
if [[ "$OS_NAME" == "Linux" ]]; then
    mkdir -p "$HOME/.config/hypr"
    copy_required "$SCRIPT_DIR/hypr/looknfeel.conf" "$HOME/.config/hypr/looknfeel.conf"
fi

# Arch/Omarchy Specific Configuration
if [[ -f /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    if [[ "${ID:-}" == "arch" || "${ID_LIKE:-}" == *"arch"* ]]; then
         copy_required "$SCRIPT_DIR/xdg/xdg-terminals.list" "$HOME/.config/xdg-terminals.list"

         # Waybar: Show battery percentage
         # Patch the existing file to preserve other Omarchy defaults instead of overwriting
         WAYBAR_CONFIG="$HOME/.config/waybar/config.jsonc"
         if [[ -f "$WAYBAR_CONFIG" ]]; then
             before_hash=$(cksum < "$WAYBAR_CONFIG")
             sed -i 's/"format-discharging": "{icon}"/"format-discharging": "{capacity}% {icon}"/' "$WAYBAR_CONFIG"
             sed -i 's/"format-charging": "{icon}"/"format-charging": "{capacity}% {icon}"/' "$WAYBAR_CONFIG"
             sed -i 's/"format-plugged": ""/"format-plugged": "{capacity}% "/' "$WAYBAR_CONFIG"
             sed -i 's/"format-full": "󰂅"/"format-full": "{capacity}% 󰂅"/' "$WAYBAR_CONFIG"
             after_hash=$(cksum < "$WAYBAR_CONFIG")

             # Restart waybar only when config changed.
             if [[ "$before_hash" != "$after_hash" ]] && command -v omarchy-restart-waybar >/dev/null; then
                 omarchy-restart-waybar || true
             fi
         fi
    fi
fi
