#!/usr/bin/env bash
# Compile plugin components with real Quickshell types, without creating their
# objects, windows, notification servers, or idle timers.
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
for module in Commons Ui services; do
  ln -s "/usr/share/omarchy/shell/$module" "$WORK/$module"
done
cat >"$WORK/shell.qml" <<'QML'
import QtQuick
import Quickshell

ShellRoot {
  Timer {
    interval: 1
    running: true
    onTriggered: {
      var files = ["andres.menu/Menu.qml", "andres.notifications/Service.qml",
                   "andres.idle/Service.qml", "andres.tray/Tray.qml"]
      for (var i = 0; i < files.length; i++) {
        var component = Qt.createComponent(
          "file://" + Quickshell.env("SMOKE_CONFIG_ROOT") + "/system/omarchy/plugins/" + files[i],
          Component.PreferSynchronous)
        if (component.status !== Component.Ready) {
          console.error("QML_CHECK_FAILED " + files[i] + ": " + component.errorString())
          Qt.quit()
          return
        }
      }
      console.log("QML_CHECK_PASSED")
      Qt.quit()
    }
  }
}
QML
status=0
SMOKE_CONFIG_ROOT="$ROOT" QS_NO_RELOAD_POPUP=1 QT_QPA_PLATFORM=wayland \
  timeout 20 quickshell --no-color --path "$WORK" >"$WORK/output" 2>&1 || status=$?
if (( status != 0 )) || ! grep -q 'QML_CHECK_PASSED' "$WORK/output"; then
  cat "$WORK/output" >&2
  exit 1
fi
echo 'Omarchy QML runtime compilation passed'
