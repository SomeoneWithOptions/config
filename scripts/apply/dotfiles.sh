# Managed config file copies; no live system state is changed here.
# Requires CHECK/DRIFT/OS_NAME/SCRIPT_DIR and lib/copy.sh.

# Pi Configuration
(( CHECK )) || mkdir -p "$HOME/code/worktrees" # /worktree extension creates worktrees here
copy_required "$SCRIPT_DIR/agents/pi/agent/AGENTS.md" "$HOME/.pi/agent/AGENTS.md"
for extension in "$SCRIPT_DIR"/agents/pi/agent/extensions/*.ts; do
    copy_required "$extension" "$HOME/.pi/agent/extensions/$(basename "$extension")"
done
# Seed only: pi writes this file itself (lastChangelogVersion, model picks made in
# the TUI). Overwriting it on every update replayed the changelog and reset models.
copy_required_if_missing "$SCRIPT_DIR/agents/pi/agent/settings.json" "$HOME/.pi/agent/settings.json"
for skill in "$SCRIPT_DIR"/agents/pi/agent/skills/*; do
    skill_name="$(basename "$skill")"
    # a-front is user-updatable: seed it once, never overwrite local edits on replay.
    [[ "$skill_name" == "a-front" && -d "$HOME/.pi/agent/skills/a-front" ]] && continue
    copy_dir_required "$skill" "$HOME/.pi/agent/skills/$skill_name"
done

# Shared agent skills (pi + Claude Code). orchestrator needs the herdr skill.
# Always create both skill dirs so Claude Code finds herdr on first launch even
# if ~/.claude does not exist yet.
for skill in "$SCRIPT_DIR"/agents/skills/*; do
    skill_name="$(basename "$skill")"
    copy_dir_required "$skill" "$HOME/.agents/skills/$skill_name"
    link_agent_skill "$skill_name" "$HOME/.pi/agent/skills" "../../../.agents/skills"
    link_agent_skill "$skill_name" "$HOME/.claude/skills" "../../.agents/skills"
done

# Fish Configuration
FISH_CONFIG_SOURCE="$SCRIPT_DIR/shell/fish/config.fish"
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

copy_required "$SCRIPT_DIR/shell/fish/conf.d/theme.fish" "$HOME/.config/fish/conf.d/theme.fish"
copy_required "$SCRIPT_DIR/shell/fish/conf.d/key_bindings.fish" "$HOME/.config/fish/conf.d/key_bindings.fish"
copy_required "$SCRIPT_DIR/shell/fish/conf.d/turso.fish" "$HOME/.config/fish/conf.d/turso.fish"
copy_required "$SCRIPT_DIR/shell/fish/functions/fish_prompt.fish" "$HOME/.config/fish/functions/fish_prompt.fish"
copy_required "$SCRIPT_DIR/shell/fish/functions/dian.fish" "$HOME/.config/fish/functions/dian.fish"

# Fontconfig / GTK Configuration
copy_required "$SCRIPT_DIR/theme/fontconfig/fonts.conf" "$HOME/.config/fontconfig/fonts.conf"
copy_required "$SCRIPT_DIR/theme/gtk-3.0/settings.ini" "$HOME/.config/gtk-3.0/settings.ini"
copy_required "$SCRIPT_DIR/theme/gtk-4.0/settings.ini" "$HOME/.config/gtk-4.0/settings.ini"
copy_required "$SCRIPT_DIR/shell/git/ignore" "$HOME/.config/git/ignore"

# Alacritty Configuration
copy_required "$SCRIPT_DIR/apps/alacritty/alacritty.toml" "$HOME/.config/alacritty/alacritty.toml"

# Ghostty Configuration
copy_required "$SCRIPT_DIR/apps/ghostty/config" "$HOME/.config/ghostty/config"

# Foot Configuration (default terminal on Linux; see xdg-terminals.list below)
copy_required "$SCRIPT_DIR/apps/foot/foot.ini" "$HOME/.config/foot/foot.ini"

# Herdr Configuration (Omarchy ships the package; this overlay is the live laptop config)
copy_required "$SCRIPT_DIR/apps/herdr/config.toml" "$HOME/.config/herdr/config.toml"

# Zed Configuration
copy_required "$SCRIPT_DIR/apps/zed/settings.json" "$HOME/.config/zed/settings.json"
copy_required "$SCRIPT_DIR/apps/zed/keymap.json" "$HOME/.config/zed/keymap.json"

if [[ "$OS_NAME" == "Darwin" ]]; then
    copy_required "$SCRIPT_DIR/apps/aerospace/aerospace.toml" "$HOME/.config/aerospace/aerospace.toml"

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

if [[ "$OS_NAME" == "Linux" ]]; then
    # Hyprland
    for hypr_file in "$SCRIPT_DIR"/system/hypr/*; do
        copy_required "$hypr_file" "$HOME/.config/hypr/$(basename "$hypr_file")"
    done

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
    copy_required "$SCRIPT_DIR/system/quickshell/flicko-picker/shell.qml" "$HOME/.config/quickshell/flicko-picker/shell.qml"
    copy_executable_required "$SCRIPT_DIR/bin/flicko-slurp" "$HOME/.local/lib/flicko-picker/slurp"
    # Optional fixed picker accent. Absent here, a machine-local color file is
    # left alone; absent in both, the picker follows the theme accent.
    if [[ -f "$SCRIPT_DIR/system/quickshell/flicko-picker/color" ]]; then
        copy_required "$SCRIPT_DIR/system/quickshell/flicko-picker/color" "$HOME/.config/quickshell/flicko-picker/color"
    fi

    for plugin in "$SCRIPT_DIR"/system/omarchy/plugins/andres.*; do
        copy_dir_required "$plugin" "$HOME/.config/omarchy/plugins/$(basename "$plugin")"
    done
    copy_required "$SCRIPT_DIR/system/omarchy/extensions/omarchy-menu.jsonc" "$HOME/.config/omarchy/extensions/omarchy-menu.jsonc"
    copy_required "$SCRIPT_DIR/system/omarchy/shell.json" "$HOME/.config/omarchy/shell.json"
    copy_required "$SCRIPT_DIR/system/omarchy/shell.toml" "$HOME/.config/omarchy/shell.toml"

    # XDG defaults
    copy_required "$SCRIPT_DIR/system/xdg/xdg-terminals.list" "$HOME/.config/xdg-terminals.list"
    # Seed only: apps append their own associations here (xdg-mime, browser
    # "set as default" buttons). A plain copy reverted those on every update.
    copy_required_if_missing "$SCRIPT_DIR/system/xdg/mimeapps.list" "$HOME/.config/mimeapps.list"

    # Zen prefs + chrome CSS. The CSS hides native window controls and assumes the
    # Omarchy/Hyprland shell. Profile dirs are randomly named, so fan out over all
    # of them. Zen only creates a profile on first launch: if none exists yet,
    # launch Zen once and re-run this script.
    zen_profiles_found=0
    for zen_profile in "$HOME"/.config/zen/*/; do
        [[ -f "$zen_profile/times.json" || -f "$zen_profile/prefs.js" ]] || continue
        copy_required "$SCRIPT_DIR/apps/zen/user.js" "$zen_profile/user.js"
        copy_required "$SCRIPT_DIR/apps/zen/userChrome.css" "$zen_profile/chrome/userChrome.css"
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
    copy_required "$SCRIPT_DIR/system/omarchy/branding/about.txt" "$HOME/.config/omarchy/branding/about.txt"
    copy_required "$SCRIPT_DIR/system/omarchy/branding/screensaver.txt" "$HOME/.config/omarchy/branding/screensaver.txt"
    for hook_dir in "$SCRIPT_DIR"/system/omarchy/hooks/*.d; do
        event="$(basename "$hook_dir")"
        for hook in "$hook_dir"/*; do
            copy_executable_required "$hook" "$HOME/.config/omarchy/hooks/$event/$(basename "$hook")"
        done
    done

    # Custom user systemd units/timers
    for unit in "$SCRIPT_DIR"/system/systemd/user/*; do
        copy_required "$unit" "$HOME/.config/systemd/user/$(basename "$unit")"
    done
fi
