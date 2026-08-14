pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland

Item {
    id: root

    property var shell
    property bool enabled: true

    FrameStyle { id: style }

    readonly property int borderWidth: style.borderWidth
    readonly property int radius: style.cornerRadius
    // Squircle instead of a circular arc. Higher power preserves more app
    // chrome near each corner. Kept with every frame metric in FrameStyle.
    readonly property real roundingPower: style.roundingPower
    // Standalone uses Waybar height; Quattro tracks shell bar height.
    readonly property int topHeight: shell && shell.bar && shell.bar.barSize
        ? shell.bar.barSize : style.topBarHeight
    // Paint past reserved gap so frame and app curves do not fight.
    readonly property int overlap: style.overlap
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

    // Wedge between the square corner and the squircle, sampled as a polyline.
    // At 18px a 24-segment fan is already sub-pixel, so no Bezier fitting needed.
    function cornerPath(r, flipX, flipY) {
        var pts = []
        for (var i = 0; i <= 24; i++) {
            var t = Math.PI / 2 * (1 - i / 24)
            var x = r * (1 - Math.pow(Math.cos(t), 2 / roundingPower))
            var y = r * (1 - Math.pow(Math.sin(t), 2 / roundingPower))
            pts.push((flipX ? r - x : x) + " " + (flipY ? r - y : y))
        }
        return "M " + (flipX ? r : 0) + " " + (flipY ? r : 0) + " L " + pts.join(" L ") + " Z"
    }

    component EdgePanel: PanelWindow {
        required property var modelData
        property string edge
        readonly property var hyprMonitor: Hyprland.monitorFor(modelData)
        readonly property bool fullscreen: hyprMonitor && hyprMonitor.activeWorkspace
            ? hyprMonitor.activeWorkspace.hasFullscreen : false

        screen: modelData
        visible: root.enabled && !fullscreen
        color: root.frameColor
        mask: Region {}
        WlrLayershell.namespace: "andres-desktop-frame-" + edge
        // These panels paint `overlap` px past what they reserve, so they have
        // to sit above the windows or that extra strip renders behind them and
        // does nothing. The top edge stays on Bottom: Waybar is already a Top
        // layer covering the same strip, and racing it would hide the bar.
        WlrLayershell.layer: edge === "top" ? WlrLayer.Bottom : WlrLayer.Top
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    }

    Variants {
        model: root.enabled ? Quickshell.screens : []

        EdgePanel {
            edge: "left"
            anchors { top: true; bottom: true; left: true }
            implicitWidth: root.borderWidth
            exclusiveZone: visible ? root.borderWidth : 0
        }
    }

    Variants {
        model: root.enabled ? Quickshell.screens : []

        EdgePanel {
            edge: "right"
            anchors { top: true; right: true; bottom: true }
            implicitWidth: root.borderWidth
            exclusiveZone: visible ? root.borderWidth : 0
        }
    }

    Variants {
        model: root.enabled ? Quickshell.screens : []

        EdgePanel {
            edge: "bottom"
            anchors { right: true; bottom: true; left: true }
            implicitHeight: root.borderWidth
            exclusiveZone: visible ? root.borderWidth : 0
        }
    }

    // Waybar/Quattro already reserves top space. This paints black behind it,
    // preserving existing compact icons without reserving a second top bar.
    Variants {
        model: root.enabled ? Quickshell.screens : []

        EdgePanel {
            edge: "top"
            anchors { top: true; right: true; left: true }
            implicitHeight: root.topHeight
            exclusionMode: ExclusionMode.Ignore
        }
    }

    // Click-through corner masks turn the square workspace into one rounded
    // viewport. Edge panels own layout; this overlay only paints the arcs.
    Variants {
        model: root.enabled ? Quickshell.screens : []

        PanelWindow {
            id: corners
            required property var modelData
            readonly property var hyprMonitor: Hyprland.monitorFor(modelData)
            readonly property bool fullscreen: hyprMonitor && hyprMonitor.activeWorkspace
                ? hyprMonitor.activeWorkspace.hasFullscreen : false
            readonly property int r: root.radius
            readonly property int leftEdge: root.borderWidth
            readonly property int rightEdge: width - root.borderWidth
            readonly property int topEdge: root.topHeight
            readonly property int bottomEdge: height - root.borderWidth

            screen: modelData
            visible: root.enabled && !fullscreen
            color: "transparent"
            surfaceFormat.opaque: false
            exclusionMode: ExclusionMode.Ignore
            mask: Region {}
            anchors { top: true; right: true; bottom: true; left: true }
            WlrLayershell.namespace: "andres-desktop-frame-corners"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

            Shape {
                x: corners.leftEdge
                y: corners.topEdge
                width: corners.r
                height: corners.r
                preferredRendererType: Shape.GeometryRenderer
                ShapePath {
                    strokeWidth: 0
                    fillColor: root.frameColor
                    PathSvg { path: "M 0 0 L " + corners.r + " 0 A " + corners.r + " " + corners.r + " 0 0 0 0 " + corners.r + " Z" }
                }
            }

            Shape {
                x: corners.rightEdge - corners.r
                y: corners.topEdge
                width: corners.r
                height: corners.r
                preferredRendererType: Shape.GeometryRenderer
                ShapePath {
                    strokeWidth: 0
                    fillColor: root.frameColor
                    PathSvg { path: "M 0 0 L " + corners.r + " 0 L " + corners.r + " " + corners.r + " A " + corners.r + " " + corners.r + " 0 0 0 0 0 Z" }
                }
            }

            Shape {
                x: corners.leftEdge
                y: corners.bottomEdge - corners.r
                width: corners.r
                height: corners.r
                preferredRendererType: Shape.GeometryRenderer
                ShapePath {
                    strokeWidth: 0
                    fillColor: root.frameColor
                    PathSvg { path: "M 0 0 A " + corners.r + " " + corners.r + " 0 0 0 " + corners.r + " " + corners.r + " L 0 " + corners.r + " Z" }
                }
            }

            Shape {
                x: corners.rightEdge - corners.r
                y: corners.bottomEdge - corners.r
                width: corners.r
                height: corners.r
                preferredRendererType: Shape.GeometryRenderer
                ShapePath {
                    strokeWidth: 0
                    fillColor: root.frameColor
                    PathSvg { path: "M " + corners.r + " 0 L " + corners.r + " " + corners.r + " L 0 " + corners.r + " A " + corners.r + " " + corners.r + " 0 0 0 " + corners.r + " 0 Z" }
                }
            }
        }
    }
}
