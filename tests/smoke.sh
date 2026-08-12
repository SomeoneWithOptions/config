#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

bash -n "$ROOT/1 SoftwareInstall.sh" "$ROOT/2 Fonts.sh" "$ROOT/3 Git.sh" \
  "$ROOT/4 ConfigFiles.sh" "$ROOT/5 Keys.sh" "$ROOT/bootstrap.sh" \
  "$ROOT"/bin/* "$ROOT"/waybar/scripts/* "$ROOT"/omarchy/hooks/*.d/*
python -m json.tool "$ROOT/waybar/config.jsonc" >/dev/null
for script in battery-power-profile idle notification-silencing screen-recording; do
  grep -q "~/.config/waybar/scripts/$script.sh" "$ROOT/waybar/config.jsonc"
  test -x "$ROOT/waybar/scripts/$script.sh"
done
test -f "$ROOT/fonts/material-symbols-rounded/MaterialSymbolsRounded.ttf"
python -m json.tool "$ROOT/zed/settings.json" >/dev/null
python -m json.tool "$ROOT/pi/agent/settings.json" >/dev/null
node "$ROOT/pi/agent/extensions/worktree.ts" --self-test >/dev/null
if command -v qmllint >/dev/null 2>&1; then
  QMLLINT=/usr/lib/qt6/bin/qmllint
  [[ -x $QMLLINT ]] || QMLLINT=$(command -v qmllint)
  "$QMLLINT" -I /usr/lib/qt6/qml "$ROOT/quickshell/flicko-picker/shell.qml"
  for qml in FrameStyle.qml FrameJoin.qml FrameService.qml Launcher.qml Notifications.qml TopBar.qml shell.qml; do
    "$QMLLINT" -I /usr/lib/qt6/qml "$ROOT/quickshell/desktop-frame/$qml"
  done
fi
python -m json.tool "$ROOT/quickshell/desktop-frame/manifest.json" >/dev/null

# A theme rename that misses config.toml or the installer leaves walker unstyled
# with no error, so pin both to the same directory.
WALKER_THEME=$(sed -n 's/^theme = "\([^"]*\)".*/\1/p' "$ROOT/walker/config.toml")
test -d "$ROOT/walker/themes/$WALKER_THEME"
grep -q "walker/themes/$WALKER_THEME\"" "$ROOT/4 ConfigFiles.sh"

# omarchy-frame owns the gaps/rounding that make the frame flush, and the on/off
# flag it keys off is easy to invert.
frame_tmp="$(mktemp -d)"
run_frame() {
  DESKTOP_FRAME_HYPR_CONFIG="$frame_tmp/desktop-frame.conf" \
    XDG_STATE_HOME="$frame_tmp/state" PATH="/nonexistent:/usr/bin:/bin" \
    "$ROOT/bin/omarchy-frame" "$@"
}
run_frame configure
grep -qx '    gaps_out = 0' "$frame_tmp/desktop-frame.conf"
grep -qx '    rounding = 18' "$frame_tmp/desktop-frame.conf"
# Waybar must stay suppressed while the frame owns the top bar, and come back
# when it does not. Inverting this stacks two bars on a fresh machine.
test -e "$frame_tmp/state/omarchy/toggles/waybar-off"
touch "$frame_tmp/state/omarchy/desktop-frame-off"
run_frame configure
grep -qx '    gaps_out = 10' "$frame_tmp/desktop-frame.conf"
test ! -e "$frame_tmp/state/omarchy/toggles/waybar-off"
[ "$(run_frame status)" = "off (original desktop)" ]
rm -rf "$frame_tmp"
if command -v quickshell >/dev/null 2>&1 && command -v hyprctl >/dev/null 2>&1 && [[ -n ${WAYLAND_DISPLAY:-} ]]; then
  FLICKO_PICKER_DIR="$ROOT/quickshell/flicko-picker" "$ROOT/bin/flicko-slurp" --self-test >/dev/null
  DESKTOP_FRAME_TEST=1 timeout 5 quickshell --no-color --path "$ROOT/quickshell/desktop-frame" >/dev/null
fi

# Hooks are fire-and-forget: `omarchy-hook` swallows failures and this one guards on
# a path, so a wrong path just exits 0 and the wallpaper silently reverts to the
# theme's stock background. Run it against a fake HOME so that stays caught.
hook_tmp="$(mktemp -d)"
mkdir -p "$hook_tmp/home/.config/omarchy/backgrounds" "$hook_tmp/bin"
printf 'x' >"$hook_tmp/home/.config/omarchy/backgrounds/chess.jpg"
for stub in pkill setsid uwsm-app swaybg; do
  printf '#!/bin/sh\nexit 0\n' >"$hook_tmp/bin/$stub"
done
chmod +x "$hook_tmp/bin"/*
run_theme_hook() {
  HOME="$hook_tmp/home" PATH="$hook_tmp/bin:$PATH" \
    bash "$ROOT/omarchy/hooks/theme-set.d/only-chess-wallpaper" "$1"
}
run_theme_hook catppuccin
test -f "$hook_tmp/home/.config/omarchy/current/theme/backgrounds/chess.jpg"
[ "$(readlink "$hook_tmp/home/.config/omarchy/current/background")" \
  = "$hook_tmp/home/.config/omarchy/current/theme/backgrounds/chess.jpg" ]
run_theme_hook tokyo-night # other themes keep their own wallpaper
rm -rf "$hook_tmp"

# Migrations rewrite ~/.config in place during `omarchy update`, so the post-update
# hook reapplying this repo is the only thing keeping customizations. Its missing-repo
# guard must exit 0 rather than run the installer from a bad path.
test -x "$ROOT/omarchy/hooks/post-update.d/reapply-user-config"
grep -q 'post-update.d/reapply-user-config' "$ROOT/4 ConfigFiles.sh"
# A missing checkout must fail loudly. Exiting 0 here is how a new laptop would go
# unprotected without ever saying so.
! CONFIG_REPO=/nonexistent PATH=/usr/bin:/bin \
  bash "$ROOT/omarchy/hooks/post-update.d/reapply-user-config" >/dev/null 2>&1
# The hook's default path must be the checkout the installer guarantees exists.
grep -q 'CONFIG_REPO:-\$HOME/code/config' "$ROOT/omarchy/hooks/post-update.d/reapply-user-config"
grep -q 'CONFIG_REPO="\$HOME/code/config"' "$ROOT/4 ConfigFiles.sh"

# Zen: the top-edge hover fix needs both halves, chrome CSS is inert without the pref.
grep -q 'legacyUserProfileCustomizations.stylesheets", true' "$ROOT/zen/user.js"
grep -q '#zen-appcontent-navbar-wrapper' "$ROOT/zen/userChrome.css"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/power/AC0" "$tmp/runtime"
printf 'Mains\n' >"$tmp/power/AC0/type"
printf '0\n' >"$tmp/power/AC0/online"
cat >"$tmp/bin/powerprofilesctl" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$CALLS"
EOF
chmod +x "$tmp/bin/powerprofilesctl"
export CALLS="$tmp/calls"

run_battery_mode() {
  POWER_SUPPLY_ROOT="$tmp/power" XDG_RUNTIME_DIR="$tmp/runtime" \
    PATH="$tmp/bin:$PATH" "$ROOT/bin/battery-power-mode"
}

run_battery_mode
run_battery_mode
[ "$(wc -l <"$CALLS")" -eq 1 ]
grep -qx 'set power-saver' "$CALLS"
printf '1\n' >"$tmp/power/AC0/online"
run_battery_mode
tail -n 1 "$CALLS" | grep -qx 'set balanced'

printf 'smoke tests passed\n'
