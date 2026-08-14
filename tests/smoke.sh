#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

bash -n "$ROOT/1 SoftwareInstall.sh" "$ROOT/2 Fonts.sh" "$ROOT/3 Git.sh" \
  "$ROOT/4 ConfigFiles.sh" "$ROOT/5 Keys.sh" "$ROOT/bootstrap.sh" \
  "$ROOT"/bin/* "$ROOT"/omarchy/hooks/*.d/*
python -m json.tool "$ROOT/omarchy/shell.json" >/dev/null
python - "$ROOT/omarchy/install-framed-panels.py" <<'PY'
import sys
compile(open(sys.argv[1]).read(), sys.argv[1], "exec")
PY
if [[ -f /usr/share/omarchy/shell/Ui/KeyboardPanel.qml ]]; then
  framed_panels_tmp="$(mktemp -d)"
  OMARCHY_CONFIG_ROOT="$framed_panels_tmp" python "$ROOT/omarchy/install-framed-panels.py"
  test -z "$(OMARCHY_CONFIG_ROOT="$framed_panels_tmp" python "$ROOT/omarchy/install-framed-panels.py")"
  for panel in audio bluetooth clock monitor network power; do
    python -m json.tool "$framed_panels_tmp/plugins/andres.$panel/manifest.json" >/dev/null
    grep -q '  FramePanel {' "$framed_panels_tmp/plugins/andres.$panel/Panel.qml"
    grep -q 'property int gap: -1' "$framed_panels_tmp/plugins/andres.$panel/FramePanel.qml"
    grep -q 'bottomRightRadius: root.attachedRight ? 0' "$framed_panels_tmp/plugins/andres.$panel/FramePanel.qml"
    grep -A4 'id: card' "$framed_panels_tmp/plugins/andres.$panel/FramePanel.qml" | grep -q 'y: 0'
    grep -q 'id: revealClip' "$framed_panels_tmp/plugins/andres.$panel/FramePanel.qml"
    grep -q 'duration: root.reduceMotion ? 0' "$framed_panels_tmp/plugins/andres.$panel/FramePanel.qml"
  done
  rm -rf "$framed_panels_tmp"
fi
for plugin in andres.desktop-frame andres.workspaces andres.menu andres.notifications andres.tray andres.idle andres.pill; do
  python -m json.tool "$ROOT/omarchy/plugins/$plugin/manifest.json" >/dev/null
  grep -q "\"id\": \"$plugin\"" "$ROOT/omarchy/shell.json"
  grep -q "omarchy/plugins/$plugin" "$ROOT/4 ConfigFiles.sh"
  if command -v omarchy-plugin-validate >/dev/null 2>&1; then
    omarchy-plugin-validate "$ROOT/omarchy/plugins/$plugin"
  fi
done
python -c 'import sys, tomllib; tomllib.load(open(sys.argv[1], "rb"))' "$ROOT/omarchy/shell.toml"
for lua in "$ROOT"/hypr/*.lua; do luac -p "$lua"; done
test -f "$ROOT/fonts/material-symbols-rounded/MaterialSymbolsRounded.ttf"
python -m json.tool "$ROOT/zed/settings.json" >/dev/null
python -m json.tool "$ROOT/pi/agent/settings.json" >/dev/null
node "$ROOT/pi/agent/extensions/worktree.ts" --self-test >/dev/null
if command -v qmllint >/dev/null 2>&1; then
  QMLLINT=/usr/lib/qt6/bin/qmllint
  [[ -x $QMLLINT ]] || QMLLINT=$(command -v qmllint)
  "$QMLLINT" -I /usr/lib/qt6/qml "$ROOT/quickshell/flicko-picker/shell.qml"
  for qml in FrameStyle.qml FrameJoin.qml FrameService.qml Launcher.qml; do
    "$QMLLINT" -I /usr/lib/qt6/qml "$ROOT/omarchy/plugins/andres.desktop-frame/$qml"
  done
  "$QMLLINT" -I /usr/lib/qt6/qml -I /usr/share/omarchy/shell "$ROOT/omarchy/plugins/andres.menu/FrameJoin.qml" "$ROOT/omarchy/plugins/andres.menu/Menu.qml"
  "$QMLLINT" -I /usr/lib/qt6/qml -I /usr/share/omarchy/shell "$ROOT/omarchy/plugins/andres.notifications/FrameJoin.qml" "$ROOT/omarchy/plugins/andres.notifications/Service.qml"
fi
if command -v quickshell >/dev/null 2>&1 && command -v hyprctl >/dev/null 2>&1 && [[ -n ${WAYLAND_DISPLAY:-} ]]; then
  FLICKO_PICKER_DIR="$ROOT/quickshell/flicko-picker" "$ROOT/bin/flicko-slurp" --self-test >/dev/null
fi

# The gamma keys are silent without an OSD, and Quattro renamed the client the
# old script called (omarchy-swayosd-client -> omarchy-osd).
grep -q 'omarchy-osd ' "$ROOT/bin/hyprsunset-gamma-display"
command -v omarchy-osd >/dev/null 2>&1 || echo "warning: omarchy-osd not found in PATH" >&2

# Migrations rewrite ~/.config in place during `omarchy update`, so the post-update
# hook reapplying this repo is the only thing keeping customizations. Its missing-repo
# guard must fail loudly rather than run the installer from a bad path.
test -x "$ROOT/omarchy/hooks/post-update.d/reapply-user-config"
grep -q 'post-update.d/reapply-user-config' "$ROOT/4 ConfigFiles.sh"
# A missing checkout must fail loudly. Exiting 0 here is how a new laptop would go
# unprotected without ever saying so. notify-send is stubbed: the guard's whole job is
# to shout, and unstubbed it shouts at the real desktop on every test run.
notify_stub="$(mktemp -d)"
printf '#!/bin/sh\nexit 0\n' >"$notify_stub/notify-send"
chmod +x "$notify_stub/notify-send"
! CONFIG_REPO=/nonexistent PATH="$notify_stub:/usr/bin:/bin" \
  bash "$ROOT/omarchy/hooks/post-update.d/reapply-user-config" >/dev/null 2>&1
rm -rf "$notify_stub"
# The hook's default path must be the checkout the installer guarantees exists.
grep -q 'CONFIG_REPO:-\$HOME/code/config' "$ROOT/omarchy/hooks/post-update.d/reapply-user-config"
grep -q 'CONFIG_REPO="\$HOME/code/config"' "$ROOT/4 ConfigFiles.sh"
# a-front is user-updatable; config replay may seed it, never overwrite it.
grep -q '\[\[ ! -d "\$HOME/.pi/agent/skills/a-front" \]\]' "$ROOT/4 ConfigFiles.sh"

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
