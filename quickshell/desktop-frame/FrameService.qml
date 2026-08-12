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
    readonly property int borderWidth: 12
    readonly property int radius: 18
    // Standalone: matches Waybar's 29px window so the black top strip reaches
    // the app's flush edge. Quattro: tracks the shell bar's own height.
    readonly property int topHeight: shell && shell.bar && shell.bar.barSize
        ? shell.bar.barSize : 29
    readonly property color frameColor: "#000000"

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
        WlrLayershell.layer: WlrLayer.Bottom
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
                preferredRendererType: Shape.CurveRenderer
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
                preferredRendererType: Shape.CurveRenderer
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
                preferredRendererType: Shape.CurveRenderer
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
                preferredRendererType: Shape.CurveRenderer
                ShapePath {
                    strokeWidth: 0
                    fillColor: root.frameColor
                    PathSvg { path: "M " + corners.r + " 0 L " + corners.r + " " + corners.r + " L 0 " + corners.r + " A " + corners.r + " " + corners.r + " 0 0 0 " + corners.r + " 0 Z" }
                }
            }
        }
    }
}
