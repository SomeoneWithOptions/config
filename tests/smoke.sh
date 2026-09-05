#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

for script in "$ROOT/1 SoftwareInstall.sh" "$ROOT/2 Fonts.sh" "$ROOT/3 Git.sh" \
  "$ROOT/4 ConfigFiles.sh" "$ROOT/5 Keys.sh" "$ROOT/bootstrap.sh" \
  "$ROOT"/bin/* "$ROOT"/omarchy/hooks/*.d/* "$ROOT/lib/report.sh" \
  "$ROOT/tests/bootstrap.sh" "$ROOT/tests/software-install.sh"; do
  # bin/ also contains Python helpers. Only shell scripts belong in bash -n.
  IFS= read -r shebang <"$script"
  case "$shebang" in
    '#!'*bash*|'#!'*/sh|'#!'*'env sh') bash -n "$script" ;;
  esac
done
sh -n "$ROOT/bootstrap.sh"
bash "$ROOT/tests/bootstrap.sh"
bash "$ROOT/tests/software-install.sh"
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
    grep -q 'id: openRevealTimer' "$framed_panels_tmp/plugins/andres.$panel/FramePanel.qml"
    grep -q 'duration: root.reduceMotion ? 0' "$framed_panels_tmp/plugins/andres.$panel/FramePanel.qml"
    grep -q 'easing.type: root.open ? Easing.OutCubic : Easing.OutExpo' "$framed_panels_tmp/plugins/andres.$panel/FramePanel.qml"
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
grep -q 'id: openRevealTimer' "$tray_plugin/FramePanel.qml"
grep -q 'easing.type: root.open ? Easing.OutCubic : Easing.OutExpo' "$tray_plugin/FramePanel.qml"
grep -q 'onWantsOpenChanged: syncReveal()' "$ROOT/omarchy/plugins/andres.notifications/Service.qml"
grep -q 'Behavior on height' "$ROOT/omarchy/plugins/andres.notifications/Service.qml"
python -c 'import sys, tomllib; tomllib.load(open(sys.argv[1], "rb"))' "$ROOT/omarchy/shell.toml"
for lua in "$ROOT"/hypr/*.lua; do luac -p "$lua"; done
test -f "$ROOT/fonts/material-symbols-rounded/MaterialSymbolsRounded.ttf"
python -m json.tool "$ROOT/zed/settings.json" >/dev/null
python -m json.tool "$ROOT/pi/agent/settings.json" >/dev/null
# Pi web research source must ship in repo; ConfigFiles installs every tracked
# extension on fresh machines and config replays.
test -f "$ROOT/pi/agent/extensions/web-research.ts"
grep -q 'name: "web_search"' "$ROOT/pi/agent/extensions/web-research.ts"
grep -q 'for extension in "\$SCRIPT_DIR"/pi/agent/extensions/\*.ts' "$ROOT/4 ConfigFiles.sh"
grep -q 'copy_required "\$extension" "\$HOME/.pi/agent/extensions/\$(basename "\$extension")"' "$ROOT/4 ConfigFiles.sh"
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

# Migrations rewrite ~/.config in place during `omarchy update`. The post-update
# hook only reports that drift; it must never write. Run --check against an empty
# HOME: everything is "missing", and HOME must stay empty afterwards.
hook="$ROOT/omarchy/hooks/post-update.d/report-config-drift"
test -x "$hook"
grep -q 'omarchy/hooks/\*\.d' "$ROOT/4 ConfigFiles.sh"
check_home="$(mktemp -d)"
check_out="$(mktemp)"
HOME="$check_home" bash "$ROOT/4 ConfigFiles.sh" --check >"$check_out" 2>&1
test -z "$(ls -A "$check_home")"
grep -q "^== $check_home/.config/fish/config.fish: missing" "$check_out"
grep -q "^== $check_home/.pi/agent/AGENTS.md: missing" "$check_out"
grep -q 'managed target(s) differ from the repo' "$check_out"
rm -rf "$check_home" "$check_out"
# Notifications are stubbed: the hook's job is to shout, and unstubbed it shouts at
# the real desktop on every test run.
notify_stub="$(mktemp -d)"
for cmd in notify-send omarchy-notification-send; do
  printf '#!/bin/sh\nexit 0\n' >"$notify_stub/$cmd"
  chmod +x "$notify_stub/$cmd"
done
# A missing checkout must fail loudly. Exiting 0 here is how a new laptop would go
# unwatched without ever saying so.
! CONFIG_REPO=/nonexistent PATH="$notify_stub:/usr/bin:/bin" \
  bash "$hook" >/dev/null 2>&1
# With a checkout the hook writes only its report, exits 0, and counts headers.
drift_report="$(mktemp -u)"
CONFIG_REPO="$ROOT" CONFIG_DRIFT_REPORT="$drift_report" PATH="$notify_stub:$PATH" \
  bash "$hook" >/dev/null 2>&1
if [[ -f $drift_report ]]; then
  grep -q '^== ' "$drift_report"
fi
rm -rf "$notify_stub" "$drift_report"
# The hook's default path must be the checkout the installer guarantees exists.
grep -q 'CONFIG_REPO:-\$HOME/code/config' "$hook"
grep -q 'CONFIG_REPO="\$HOME/code/config"' "$ROOT/4 ConfigFiles.sh"
# Config replay owns shell.json, so externally installed widgets must stay in
# that source of truth after their installers run.
grep -q '"id": "loom.recording"' "$ROOT/omarchy/shell.json"
grep -q '"id": "andres.linear"' "$ROOT/omarchy/shell.json"
# Fresh-laptop tool installs must use each project's unattended curl path.
grep -q 'go.sanetomore.com/commiter' "$ROOT/1 SoftwareInstall.sh"
grep -q 'SomeoneWithOptions/loom-omarchy-linux/main/install.sh' "$ROOT/1 SoftwareInstall.sh"
grep -q 'SomeoneWithOptions/linear-omarchy-plugin/main/install.sh' "$ROOT/1 SoftwareInstall.sh"
grep -q 'bash -s -- --yes' "$ROOT/1 SoftwareInstall.sh"
# a-front is user-updatable; config replay may seed it, never overwrite it.
grep -q 'a-front" && -d "\$HOME/.pi/agent/skills/a-front" \]\] && continue' "$ROOT/4 ConfigFiles.sh"

# Zen: the top-edge hover fix needs both halves, chrome CSS is inert without the pref.
grep -q 'legacyUserProfileCustomizations.stylesheets", true' "$ROOT/zen/user.js"
grep -q '#zen-appcontent-navbar-wrapper' "$ROOT/zen/userChrome.css"

printf 'smoke tests passed\n'
