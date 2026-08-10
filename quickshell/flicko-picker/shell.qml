import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

ShellRoot {
    id: root

    readonly property string outputPath: Quickshell.env("FLICKO_OUTPUT") || ""
    readonly property color accent: Quickshell.env("FLICKO_ACCENT") || "#89b4fa"
    readonly property color background: Quickshell.env("FLICKO_BACKGROUND") || "#1e1e2e"
    property string activeScreenName: Quickshell.env("FLICKO_SCREEN") || ""
    property bool selecting: false
    property real startX: 0
    property real startY: 0
    property real endX: 0
    property real endY: 0

    readonly property real left: Math.min(startX, endX)
    readonly property real top: Math.min(startY, endY)
    readonly property real right: Math.max(startX, endX)
    readonly property real bottom: Math.max(startY, endY)

    function begin(screen, x, y) {
        activeScreenName = screen.name
        startX = endX = screen.x + x
        startY = endY = screen.y + y
        selecting = true
    }

    function update(screen, x, y) {
        endX = screen.x + x
        endY = screen.y + y
    }

    function writeResult(value) {
        if (outputPath) resultFile.setText(value)
        Qt.callLater(Qt.quit)
    }

    function finish() {
        var x = Math.round(left)
        var y = Math.round(top)
        var width = Math.max(1, Math.round(right) - x)
        var height = Math.max(1, Math.round(bottom) - y)
        selecting = false
        writeResult(x + "," + y + " " + width + "x" + height + "\n")
    }

    function fullscreen(screen) {
        startX = screen.x
        startY = screen.y
        endX = screen.x + screen.width
        endY = screen.y + screen.height
        finish()
    }

    function cancel() {
        selecting = false
        writeResult("")
    }

    component ElasticRope: Shape {
        id: rope
        property real anchorX: 0
        property real anchorY: 0
        property real targetX: 0
        property real targetY: 0
        readonly property real distance: Math.hypot(targetX - anchorX, targetY - anchorY)
        readonly property real sag: Math.min(90, distance * 0.08)

        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            strokeColor: root.accent
            strokeWidth: 4
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin
            fillColor: "transparent"
            startX: rope.anchorX
            startY: rope.anchorY

            PathCubic {
                x: rope.targetX
                y: rope.targetY
                control1X: rope.anchorX + (rope.targetX - rope.anchorX) * 0.38
                control1Y: rope.anchorY + (rope.targetY - rope.anchorY) * 0.38 + rope.sag
                control2X: rope.anchorX + (rope.targetX - rope.anchorX) * 0.76
                control2Y: rope.anchorY + (rope.targetY - rope.anchorY) * 0.76 + rope.sag * 0.55

                Behavior on control1X { SpringAnimation { spring: 2.4; damping: 0.22 } }
                Behavior on control1Y { SpringAnimation { spring: 2.4; damping: 0.22 } }
                Behavior on control2X { SpringAnimation { spring: 2.8; damping: 0.24 } }
                Behavior on control2Y { SpringAnimation { spring: 2.8; damping: 0.24 } }
            }
        }
    }

    FileView {
        id: resultFile
        path: root.outputPath
        blockWrites: true
        atomicWrites: false
    }

    Component.onCompleted: {
        if (Quickshell.env("FLICKO_TEST") === "1")
            writeResult("10,20 300x200\n")
    }

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: panel
            property var modelData
            screen: modelData
            visible: Quickshell.env("FLICKO_TEST") !== "1"
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            anchors { top: true; right: true; bottom: true; left: true }
            WlrLayershell.namespace: "flicko-region-picker"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: panel.screen.name === root.activeScreenName
                ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

            Item {
                id: stage
                anchors.fill: parent
                focus: panel.screen.name === root.activeScreenName

                readonly property real selectionLeft: root.left - panel.screen.x
                readonly property real selectionTop: root.top - panel.screen.y
                readonly property real selectionRight: root.right - panel.screen.x
                readonly property real selectionBottom: root.bottom - panel.screen.y
                readonly property real clippedLeft: Math.max(0, Math.min(width, selectionLeft))
                readonly property real clippedTop: Math.max(0, Math.min(height, selectionTop))
                readonly property real clippedRight: Math.max(0, Math.min(width, selectionRight))
                readonly property real clippedBottom: Math.max(0, Math.min(height, selectionBottom))
                readonly property bool intersects: clippedRight > clippedLeft && clippedBottom > clippedTop

                Keys.onPressed: event => {
                    if (event.key === Qt.Key_Escape) {
                        root.cancel()
                        event.accepted = true
                    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                        root.fullscreen(panel.screen)
                        event.accepted = true
                    }
                }

                Rectangle {
                    anchors.fill: parent
                    color: root.background
                    opacity: 0.78
                    visible: !root.selecting || !stage.intersects
                }

                Rectangle {
                    x: 0; y: 0; width: parent.width; height: stage.clippedTop
                    color: root.background; opacity: 0.78
                    visible: root.selecting && stage.intersects
                }
                Rectangle {
                    x: 0; y: stage.clippedBottom
                    width: parent.width; height: parent.height - y
                    color: root.background; opacity: 0.78
                    visible: root.selecting && stage.intersects
                }
                Rectangle {
                    x: 0; y: stage.clippedTop
                    width: stage.clippedLeft; height: stage.clippedBottom - stage.clippedTop
                    color: root.background; opacity: 0.78
                    visible: root.selecting && stage.intersects
                }
                Rectangle {
                    x: stage.clippedRight; y: stage.clippedTop
                    width: parent.width - x; height: stage.clippedBottom - stage.clippedTop
                    color: root.background; opacity: 0.78
                    visible: root.selecting && stage.intersects
                }

                Item {
                    anchors.fill: parent
                    visible: root.selecting && panel.screen.name === root.activeScreenName

                    ElasticRope {
                        anchors.fill: parent
                        anchorX: 0; anchorY: 0
                        targetX: stage.selectionLeft; targetY: stage.selectionTop
                    }
                    ElasticRope {
                        anchors.fill: parent
                        anchorX: parent.width; anchorY: 0
                        targetX: stage.selectionRight; targetY: stage.selectionTop
                    }
                    ElasticRope {
                        anchors.fill: parent
                        anchorX: 0; anchorY: parent.height
                        targetX: stage.selectionLeft; targetY: stage.selectionBottom
                    }
                    ElasticRope {
                        anchors.fill: parent
                        anchorX: parent.width; anchorY: parent.height
                        targetX: stage.selectionRight; targetY: stage.selectionBottom
                    }
                }

                Rectangle {
                    x: stage.selectionLeft
                    y: stage.selectionTop
                    width: Math.max(0, stage.selectionRight - stage.selectionLeft)
                    height: Math.max(0, stage.selectionBottom - stage.selectionTop)
                    color: "transparent"
                    border.color: root.accent
                    border.width: 4
                    visible: root.selecting
                }

                Repeater {
                    model: root.selecting ? [
                        [stage.selectionLeft, stage.selectionTop],
                        [stage.selectionRight, stage.selectionTop],
                        [stage.selectionLeft, stage.selectionBottom],
                        [stage.selectionRight, stage.selectionBottom]
                    ] : []

                    Rectangle {
                        required property var modelData
                        x: modelData[0] - width / 2
                        y: modelData[1] - height / 2
                        width: 26
                        height: 26
                        radius: 13
                        color: root.accent
                    }
                }

                MouseArea {
                    id: pointer
                    anchors.fill: parent
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    hoverEnabled: true
                    cursorShape: Qt.BlankCursor
                    onPressed: mouse => {
                        if (mouse.button === Qt.RightButton) root.cancel()
                        else root.begin(panel.screen, mouse.x, mouse.y)
                    }
                    onPositionChanged: mouse => {
                        if (pressed && mouse.buttons & Qt.LeftButton)
                            root.update(panel.screen, mouse.x, mouse.y)
                    }
                    onReleased: mouse => {
                        if (mouse.button === Qt.LeftButton && root.selecting)
                            root.finish()
                    }
                }

                Rectangle {
                    x: pointer.mouseX - width / 2
                    y: pointer.mouseY - height / 2
                    width: 26
                    height: 26
                    radius: 13
                    color: root.accent
                    visible: pointer.containsMouse && !root.selecting
                }
            }
        }
    }
}
