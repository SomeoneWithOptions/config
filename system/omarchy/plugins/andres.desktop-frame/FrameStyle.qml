import QtQuick
import qs.Commons

// Shared geometry for the top strip and every Quickshell edge drawer.
QtObject {
    // Distance from screen edge — mirrors Hyprland general:gaps_out so
    // drawers line up with tiled windows.  Keep in sync with FramePanel.
    readonly property int edgeInset: Style.gapsOut > 0 ? Style.gapsOut * 2 : 10
    // Radius for the bar-adjacent drawer edge (subtle, not window-rounding)
    readonly property int cornerRadius: 12
    // Nook radius at the four desktop corners — follows Hyprland
    // decoration:rounding via Style.cornerRadius so frame curves like
    // windows inside it. Set to 0 to drop the corner decorations.
    readonly property int screenCornerRadius: Style.cornerRadius > 0 ? Style.cornerRadius : 18
    readonly property int topBarHeight: 42
    // Drawers tuck 1px under the top strip. On fractional scale the strip's
    // bottom edge and a drawer at the same logical y round to different
    // device pixels, leaving a 1px seam of desktop showing between them.
    // With feathered FrameJoin that seam is invisible, but overlap stays
    // to guarantee no hairline on integer scales.
    readonly property int drawerTop: topBarHeight - 1
    readonly property color frameColor: "#000000"
}
