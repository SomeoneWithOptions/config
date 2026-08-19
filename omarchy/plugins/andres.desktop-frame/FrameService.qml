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
    readonly property int cornerRadius: style.screenCornerRadius

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

    // Black nooks at the four desktop corners: under the top strip and at the
    // screen's bottom edge. Only the gap rows are painted, so windows keep
    // their own rounding and the frame reads as one continuous curve.
    Variants {
        model: root.enabled && style.screenCornerRadius > 0 ? Quickshell.screens : []

        PanelWindow {
            id: cornerPanel
            required property var modelData
            readonly property var hyprMonitor: Hyprland.monitorFor(modelData)
            readonly property bool fullscreen: hyprMonitor && hyprMonitor.activeWorkspace
                ? hyprMonitor.activeWorkspace.hasFullscreen : false
            readonly property int corner: root.cornerRadius

            screen: modelData
            visible: root.enabled && !fullscreen
            color: "transparent"
            surfaceFormat.opaque: false
            mask: Region {}
            anchors { top: true; right: true; bottom: true; left: true }
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.namespace: "andres-desktop-frame-corners"
            WlrLayershell.layer: WlrLayer.Bottom
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

            // Same 1px tuck the drawers use, so no seam shows between the strip
            // and the nook on fractional scale. The nook's top row is solid.
            Fillet { x: 0; y: root.topHeight - 1; rotation: 270 }
            Fillet { x: cornerPanel.width - cornerPanel.corner; y: root.topHeight - 1; rotation: 0 }
            Fillet { x: 0; y: cornerPanel.height - cornerPanel.corner; rotation: 180 }
            Fillet {
                x: cornerPanel.width - cornerPanel.corner
                y: cornerPanel.height - cornerPanel.corner
                rotation: 90
            }
        }
    }

    component Fillet: FrameJoin {
        width: root.cornerRadius
        height: root.cornerRadius
    }
}
