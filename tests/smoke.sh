#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

bash -n "$ROOT/1 SoftwareInstall.sh" "$ROOT/2 Fonts.sh" "$ROOT/3 Git.sh" \
  "$ROOT/4 ConfigFiles.sh" "$ROOT/5 Keys.sh" "$ROOT/bootstrap.sh" \
  "$ROOT"/bin/* "$ROOT"/waybar/scripts/*
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
  for qml in FrameStyle.qml FrameJoin.qml FrameService.qml Launcher.qml Notifications.qml shell.qml; do
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
touch "$frame_tmp/state/omarchy/desktop-frame-off"
run_frame configure
grep -qx '    gaps_out = 10' "$frame_tmp/desktop-frame.conf"
[ "$(run_frame status)" = "off (original desktop)" ]
rm -rf "$frame_tmp"
if command -v quickshell >/dev/null 2>&1 && command -v hyprctl >/dev/null 2>&1 && [[ -n ${WAYLAND_DISPLAY:-} ]]; then
  FLICKO_PICKER_DIR="$ROOT/quickshell/flicko-picker" "$ROOT/bin/flicko-slurp" --self-test >/dev/null
  DESKTOP_FRAME_TEST=1 timeout 5 quickshell --no-color --path "$ROOT/quickshell/desktop-frame" >/dev/null
fi

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
