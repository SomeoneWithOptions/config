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
  for panel in audio bluetooth clock monitor network power tailscale; do
    python -m json.tool "$framed_panels_tmp/plugins/andres.$panel/manifest.json" >/dev/null
    grep -q '  FramePanel {' "$framed_panels_tmp/plugins/andres.$panel/Panel.qml"
    grep -q 'property int gap: -1' "$framed_panels_tmp/plugins/andres.$panel/FramePanel.qml"
    grep -q 'bottomRightRadius: root.attachedRight ? 0' "$framed_panels_tmp/plugins/andres.$panel/FramePanel.qml"
    grep -A4 'id: card' "$framed_panels_tmp/plugins/andres.$panel/FramePanel.qml" | grep -q 'y: 0'
    grep -q 'id: revealClip' "$framed_panels_tmp/plugins/andres.$panel/FramePanel.qml"
    grep -q 'duration: root.reduceMotion ? 0' "$framed_panels_tmp/plugins/andres.$panel/FramePanel.qml"
  done
  # Clock belongs against right frame like neighboring status panels, not centered.
  grep -q 'centerOnBar: false' "$framed_panels_tmp/plugins/andres.clock/Panel.qml"
  ! grep -q 'centerOnBar: true' "$framed_panels_tmp/plugins/andres.clock/Panel.qml"
  # The gamma row is patched onto the stock Display panel. An upstream rename must
  # fail here rather than quietly ship a panel with the slider missing.
  grep -q 'text: "GAMMA"' "$framed_panels_tmp/plugins/andres.monitor/Panel.qml"
  grep -q '"hyprsunset-gamma-display", "--no-osd"' "$framed_panels_tmp/plugins/andres.monitor/Panel.qml"
  rm -rf "$framed_panels_tmp"
fi
# Every plugin folder is installed by one glob in the installer, so the only
# per-plugin risk left is a plugin that is shipped but never enabled in shell.json.
grep -q 'omarchy/plugins/andres\.\*' "$ROOT/4 ConfigFiles.sh"
for plugin in "$ROOT"/omarchy/plugins/andres.*; do
  python -m json.tool "$plugin/manifest.json" >/dev/null
  grep -q "\"id\": \"$(basename "$plugin")\"" "$ROOT/omarchy/shell.json"
  if command -v omarchy-plugin-validate >/dev/null 2>&1; then
    omarchy-plugin-validate "$plugin"
  fi
done
# App-provided StatusNotifier menus and tray management must share framed-panel
# geometry. Config replay uses rsync --delete, so missing helpers here would both
# restore PopupCard and remove working live files after every Omarchy update.
tray_plugin="$ROOT/omarchy/plugins/andres.tray"
test -f "$tray_plugin/FramePanel.qml"
test -f "$tray_plugin/FrameJoin.qml"
test "$(grep -c '^  FramePanel {' "$tray_plugin/Tray.qml")" -eq 2
! grep -q '^  PopupCard {' "$tray_plugin/Tray.qml"
grep -q 'property int gap: -1' "$tray_plugin/FramePanel.qml"
python -c 'import sys, tomllib; tomllib.load(open(sys.argv[1], "rb"))' "$ROOT/omarchy/shell.toml"
for lua in "$ROOT"/hypr/*.lua; do luac -p "$lua"; done
test -f "$ROOT/fonts/material-symbols-rounded/MaterialSymbolsRounded.ttf"
python -m json.tool "$ROOT/zed/settings.json" >/dev/null
python -m json.tool "$ROOT/pi/agent/settings.json" >/dev/null
node "$ROOT/pi/agent/extensions/worktree.ts" --self-test >/dev/null
node --input-type=module - "$ROOT/pi/agent/extensions/omarchy-system-theme.ts" <<'JS'
import assert from "node:assert/strict";
import { pathToFileURL } from "node:url";
const { themeMode } = await import(pathToFileURL(process.argv[2]));
assert.equal(themeMode('mode = "light"\nbackground = "#fff"'), "light");
assert.equal(themeMode('mode = "dark"'), "dark");
JS

if [[ -d /usr/share/omarchy/shell/plugins ]]; then
  (cd /usr/share/omarchy/shell/plugins &&
    sha256sum --quiet -c "$ROOT/omarchy/plugins/UPSTREAM.sha256")
fi
if [[ -x /usr/bin/omazed-generator.sh ]]; then
  omazed_tmp="$(mktemp -d)"
  mkdir -p "$omazed_tmp/.local/state/omarchy/current/theme"
  cp "$HOME/.local/state/omarchy/current/theme/colors.toml" "$omazed_tmp/.local/state/omarchy/current/theme/"
  colors="$omazed_tmp/.local/state/omarchy/current/theme/colors.toml"
  sed -i -E 's/^mode[[:space:]]*=.*/mode = "dark"/' "$colors"
  HOME="$omazed_tmp" bash "$ROOT/omarchy/hooks/theme-set.d/sync-zed-theme" >/dev/null
  grep -q '"appearance": "dark"' "$omazed_tmp/.config/zed/themes/omazed.json"
  sed -i -E 's/^mode[[:space:]]*=.*/mode = "light"/' "$colors"
  HOME="$omazed_tmp" bash "$ROOT/omarchy/hooks/theme-set.d/sync-zed-theme" >/dev/null
  grep -q '"appearance": "light"' "$omazed_tmp/.config/zed/themes/omazed.json"
  python -m json.tool "$omazed_tmp/.config/zed/themes/omazed.json" >/dev/null
  rm -rf "$omazed_tmp"
fi
if command -v qmllint >/dev/null 2>&1; then
  QMLLINT=/usr/lib/qt6/bin/qmllint
  [[ -x $QMLLINT ]] || QMLLINT=$(command -v qmllint)
  "$QMLLINT" -I /usr/lib/qt6/qml "$ROOT/quickshell/flicko-picker/shell.qml"
  for qml in FrameStyle.qml FrameJoin.qml FrameService.qml; do
    "$QMLLINT" -I /usr/lib/qt6/qml "$ROOT/omarchy/plugins/andres.desktop-frame/$qml"
  done
  "$QMLLINT" -I /usr/lib/qt6/qml -I /usr/share/omarchy/shell "$ROOT/omarchy/plugins/andres.menu/FrameJoin.qml" "$ROOT/omarchy/plugins/andres.menu/Menu.qml"
  "$QMLLINT" -I /usr/lib/qt6/qml -I /usr/share/omarchy/shell "$ROOT/omarchy/plugins/andres.notifications/FrameJoin.qml" "$ROOT/omarchy/plugins/andres.notifications/Service.qml"
  "$QMLLINT" -I /usr/lib/qt6/qml -I /usr/share/omarchy/shell "$ROOT/omarchy/plugins/andres.tray/FrameJoin.qml" "$ROOT/omarchy/plugins/andres.tray/FramePanel.qml" "$ROOT/omarchy/plugins/andres.tray/Tray.qml"
fi
if command -v quickshell >/dev/null 2>&1 && command -v hyprctl >/dev/null 2>&1 && [[ -n ${WAYLAND_DISPLAY:-} ]]; then
  FLICKO_PICKER_DIR="$ROOT/quickshell/flicko-picker" "$ROOT/bin/flicko-slurp" --self-test >/dev/null
fi

# The gamma keys are silent without an OSD, and Quattro renamed the client the
# old script called (omarchy-swayosd-client -> omarchy-osd).
grep -q 'omarchy-osd ' "$ROOT/bin/hyprsunset-gamma-display"
# The panel slider calls the same script with --no-osd; dropping that flag would
# make every drag frame summon a toast.
grep -q -- '--no-osd' "$ROOT/bin/hyprsunset-gamma-display"
command -v omarchy-osd >/dev/null 2>&1 || echo "warning: omarchy-osd not found in PATH" >&2

# Migrations rewrite ~/.config in place during `omarchy update`, so the post-update
# hook reapplying this repo is the only thing keeping customizations. Its missing-repo
# guard must fail loudly rather than run the installer from a bad path.
test -x "$ROOT/omarchy/hooks/post-update.d/reapply-user-config"
grep -q 'omarchy/hooks/\*\.d' "$ROOT/4 ConfigFiles.sh"
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
# Config replay owns shell.json, so Loom must stay in that source of truth.
grep -q '"id": "loom.recording"' "$ROOT/omarchy/shell.json"
# a-front is user-updatable; config replay may seed it, never overwrite it.
grep -q 'a-front" && -d "\$HOME/.pi/agent/skills/a-front" \]\] && continue' "$ROOT/4 ConfigFiles.sh"

# Zen: the top-edge hover fix needs both halves, chrome CSS is inert without the pref.
grep -q 'legacyUserProfileCustomizations.stylesheets", true' "$ROOT/zen/user.js"
grep -q '#zen-appcontent-navbar-wrapper' "$ROOT/zen/userChrome.css"

printf 'smoke tests passed\n'
