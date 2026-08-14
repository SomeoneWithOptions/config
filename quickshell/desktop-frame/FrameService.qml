pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland

Item {
    id: root

    property var shell
    property bool enabled: true

    FrameStyle { id: style }

    // Standalone uses Waybar height; Quattro tracks shell bar height.
    readonly property int topHeight: shell && shell.bar && shell.bar.barSize
        ? shell.bar.barSize : style.topBarHeight
    readonly property color frameColor: style.frameColor
    readonly property bool quattro: Quickshell.env("OMARCHY_PATH").startsWith("/usr/share/omarchy")

    // hypridle retires in Quattro. Preserve this laptop's battery-only
    // 15-minute suspend without running a second legacy idle daemon.
    IdleMonitor {
        enabled: root.enabled && root.quattro
        timeout: 900
        respectInhibitors: true
        onIsIdleChanged: if (isIdle) Quickshell.execDetached([
            "sh", "-c",
            "test \"$(cat /sys/class/power_supply/AC/online 2>/dev/null)\" = 0 && systemctl suspend"
        ])
    }

    // Only the top strip is painted. Left/right/bottom use Hyprland's normal
    // gaps_out, so windows sit in the same gap they use between each other.
    // The strip stays on Bottom: the bar is already a Top layer covering the
    // same rows, and racing it would hide the bar.
    Variants {
        model: root.enabled ? Quickshell.screens : []

        PanelWindow {
            required property var modelData
            readonly property var hyprMonitor: Hyprland.monitorFor(modelData)
            readonly property bool fullscreen: hyprMonitor && hyprMonitor.activeWorkspace
                ? hyprMonitor.activeWorkspace.hasFullscreen : false

            screen: modelData
            visible: root.enabled && !fullscreen
            color: root.frameColor
            mask: Region {}
            anchors { top: true; right: true; left: true }
            implicitHeight: root.topHeight
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.namespace: "andres-desktop-frame-top"
            WlrLayershell.layer: WlrLayer.Bottom
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        }
    }
}
