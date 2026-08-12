import QtQuick

// Shared geometry for frame and every Quickshell edge drawer.
QtObject {
    readonly property int borderWidth: 12
    readonly property int overlap: 7
    readonly property int edgeInset: borderWidth + overlap
    readonly property int cornerRadius: 18
    readonly property int topBarHeight: 29
    // Keep in sync with decoration:rounding_power in Hyprland looknfeel.conf.
    readonly property real roundingPower: 4.0
    readonly property color frameColor: "#000000"
}
