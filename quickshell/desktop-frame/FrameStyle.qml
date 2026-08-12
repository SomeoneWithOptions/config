import QtQuick

// Shared geometry for frame and every Quickshell edge drawer.
QtObject {
    readonly property int borderWidth: 12
    readonly property int overlap: 7
    readonly property int edgeInset: borderWidth + overlap
    readonly property int cornerRadius: 18
    readonly property int topBarHeight: 42
    // Drawers tuck 1px under the top strip. On fractional scale the strip's
    // bottom edge and a drawer at the same logical y round to different device
    // pixels, leaving a 1px seam of desktop showing between them.
    readonly property int drawerTop: topBarHeight - 1
    // Keep in sync with decoration:rounding_power in Hyprland looknfeel.conf.
    readonly property real roundingPower: 4.0
    readonly property color frameColor: "#000000"
}
