import QtQuick

// Shared geometry for the top strip and every Quickshell edge drawer.
QtObject {
    // Distance from the screen edge, matching Hyprland general:gaps_out so
    // drawers line up with tiled windows.
    readonly property int edgeInset: 10
    readonly property int cornerRadius: 12
    readonly property int topBarHeight: 42
    // Drawers tuck 1px under the top strip. On fractional scale the strip's
    // bottom edge and a drawer at the same logical y round to different device
    // pixels, leaving a 1px seam of desktop showing between them.
    readonly property int drawerTop: topBarHeight - 1
    readonly property color frameColor: "#000000"
}
