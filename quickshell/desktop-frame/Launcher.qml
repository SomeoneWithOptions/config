pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland

Item {
    id: root

    property var shell
    property bool opened: false
    property bool mounted: false
    property real reveal: 0
    property string query: ""
    property string screenName: ""
    property var applications: []
    property var results: []
    property int selectedIndex: 0
    property real filterProgress: 1
    readonly property int visibleRows: 7
    readonly property int resultLimit: 150
    readonly property int rowHeight: 54
    readonly property int rowGap: 4
    readonly property int searchHeight: 72
    readonly property int frameInset: 12
    readonly property int corner: 18
    readonly property color frameColor: "#000000"
    readonly property string uiFont: "DM Sans"
    readonly property string detailFont: "Azeret Mono"
    readonly property int closeDuration: reduceMotion ? 0 : 400
    readonly property bool reduceMotion: Quickshell.env("DESKTOP_FRAME_REDUCED_MOTION") === "1"

    function searchableText(entry) {
        return [entry.name, entry.genericName, entry.comment, (entry.keywords || []).join(" ")]
            .join(" ").toLowerCase()
    }

    function score(entry, needle) {
        if (!needle) return 0
        var name = String(entry.name || "").toLowerCase()
        if (name === needle) return 0
        if (name.indexOf(needle) === 0) return 1
        var words = name.split(/\s+/)
        for (var i = 0; i < words.length; i++)
            if (words[i].indexOf(needle) === 0) return 2
        return searchableText(entry).indexOf(needle) >= 0 ? 3 : -1
    }

    function refreshApplications() {
        var values = DesktopEntries.applications.values || []
        var next = []
        for (var i = 0; i < values.length; i++) next.push(values[i])
        next.sort(function(a, b) {
            return String(a.name || "").localeCompare(String(b.name || ""))
        })
        applications = next
        rebuildResults()
    }

    function rebuildResults() {
        var needle = query.trim().toLowerCase()
        var ranked = []
        for (var i = 0; i < applications.length; i++) {
            var rank = score(applications[i], needle)
            if (rank >= 0) ranked.push({ entry: applications[i], rank: rank })
        }
        ranked.sort(function(a, b) {
            return a.rank - b.rank || String(a.entry.name || "").localeCompare(String(b.entry.name || ""))
        })
        var next = []
        for (var j = 0; j < ranked.length && j < resultLimit; j++) next.push(ranked[j].entry)
        results = next
        selectedIndex = Math.min(Math.max(0, selectedIndex), Math.max(0, results.length - 1))
    }

    function open(payload) {
        closeTimer.stop()
        query = ""
        selectedIndex = 0
        var monitor = Hyprland.focusedMonitor
        screenName = monitor ? monitor.name : ""
        mounted = true
        opened = true
        refreshApplications()
        reveal = 0
        Qt.callLater(function() { reveal = 1 })
    }

    function close() {
        if (!mounted) return
        opened = false
        reveal = 0
        if (closeDuration === 0) mounted = false
        else closeTimer.restart()
    }

    function toggle() {
        if (opened) close()
        else open("")
    }

    function moveSelection(delta) {
        if (results.length === 0) return
        selectedIndex = (selectedIndex + delta + results.length) % results.length
    }

    function launch(entry) {
        if (!entry) return
        close()
        if (shell && shell.appLibrary) shell.appLibrary.launch(entry.id, entry.name)
        else Quickshell.execDetached(["uwsm-app", "--", "gtk-launch", entry.id + ".desktop"])
    }

    onQueryChanged: {
        selectedIndex = 0
        rebuildResults()
        if (!reduceMotion) filterAnimation.restart()
    }

    Behavior on reveal {
        NumberAnimation { duration: root.reduceMotion ? 0 : 380; easing.type: Easing.OutExpo }
    }

    NumberAnimation {
        id: filterAnimation
        target: root
        property: "filterProgress"
        from: 0
        to: 1
        duration: 300
        easing.type: Easing.OutQuart
    }

    Timer {
        id: closeTimer
        interval: root.closeDuration
        onTriggered: root.mounted = false
    }

    Connections {
        target: DesktopEntries.applications
        function onValuesChanged() { root.refreshApplications() }
    }

    IpcHandler {
        target: "desktopFrame"
        function open(): void { root.open("") }
        function close(): void { root.close() }
        function toggle(): void { root.toggle() }
    }

    Component.onCompleted: refreshApplications()

    component LauncherPanel: PanelWindow {
            id: panel
            required property var modelData
            // Fixed viewport: list scrolls inside it as the selection moves past
            // the visible rows.
            readonly property int resultAreaHeight: root.results.length > 0
                ? 16 + root.visibleRows * root.rowHeight + Math.max(0, root.visibleRows - 1) * root.rowGap
                : root.rowHeight + 16
            readonly property int fullCardHeight: root.searchHeight + resultAreaHeight
            readonly property int animatedCardHeight: Math.max(1, Math.round(fullCardHeight * root.reveal))

            screen: modelData
            visible: root.mounted && (root.screenName === "" || modelData.name === root.screenName)
            color: "transparent"
            surfaceFormat.opaque: false
            exclusionMode: ExclusionMode.Ignore
            anchors { top: true; right: true; bottom: true; left: true }
            WlrLayershell.namespace: "andres-desktop-launcher"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

            onVisibleChanged: if (visible) Qt.callLater(function() { searchInput.forceActiveFocus() })

            MouseArea {
                anchors.fill: parent
                onClicked: root.close()
            }

            Item {
                id: card
                readonly property int bodyWidth: Math.min(460, panel.width - 64)
                width: bodyWidth + 2 * root.corner
                height: panel.animatedCardHeight
                x: Math.round((panel.width - width) / 2)
                y: panel.height - root.frameInset - height
                opacity: Math.min(1, root.reveal * 1.5)

                // Same concave fillets as Notifications: body ends at frame edge;
                // side fillets visually fuse it into black bottom border.
                Rectangle {
                    x: root.corner
                    width: card.bodyWidth
                    height: parent.height
                    color: root.frameColor
                    topLeftRadius: 24
                    topRightRadius: 24
                }

                Fillet {
                    x: 0
                    y: card.height - root.corner
                    rotation: 90
                }

                Fillet {
                    x: root.corner + card.bodyWidth
                    y: card.height - root.corner
                    rotation: 180
                }

                MouseArea { anchors.fill: parent; onClicked: function(mouse) { mouse.accepted = true } }

                Item {
                    id: cardContent
                    anchors.left: parent.left
                    anchors.leftMargin: root.corner
                    anchors.right: parent.right
                    anchors.rightMargin: root.corner
                    height: panel.fullCardHeight
                    anchors.bottom: parent.bottom

                    Item {
                        id: resultArea
                        anchors.top: parent.top
                        anchors.left: parent.left
                        anchors.right: parent.right
                        height: panel.resultAreaHeight

                        ListView {
                            id: resultList
                            anchors.fill: parent
                            anchors.leftMargin: 12
                            anchors.rightMargin: 12
                            anchors.topMargin: 12
                            anchors.bottomMargin: 4
                            model: root.results
                            spacing: root.rowGap
                            interactive: false
                            clip: true

                            WheelHandler {
                                onWheel: function(event) {
                                    if (event.angleDelta.y !== 0)
                                        root.moveSelection(event.angleDelta.y > 0 ? -1 : 1)
                                }
                            }

                            // Keep the selection row in view as it moves past the visible rows.
                            Connections {
                                target: root
                                function onSelectedIndexChanged() {
                                    if (resultList.count > 0)
                                        resultList.positionViewAtIndex(root.selectedIndex, ListView.Contain)
                                }
                            }
                            opacity: 0.45 + root.filterProgress * 0.55
                            transform: Translate {
                                x: (1 - root.filterProgress) * 18
                                y: (1 - root.filterProgress) * 7
                            }

                            delegate: Rectangle {
                                id: row
                                required property var modelData
                                required property int index
                                readonly property bool selected: index === root.selectedIndex
                                readonly property string iconSource: Quickshell.iconPath(modelData.icon, true)
                                width: ListView.view.width
                                height: root.rowHeight
                                radius: 16
                                color: selected ? "#1d1d1d" : "transparent"
                                border.width: 1
                                border.color: selected ? "#3c3c3c" : "transparent"

                                Behavior on color { ColorAnimation { duration: 110 } }
                                Behavior on border.color { ColorAnimation { duration: 110 } }

                                Rectangle {
                                    id: iconWell
                                    anchors.left: parent.left
                                    anchors.leftMargin: 10
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 38
                                    height: 38
                                    radius: 13
                                    color: row.selected ? "#2a2a2a" : "#151515"

                                    Behavior on color { ColorAnimation { duration: 110 } }

                                    Image {
                                        anchors.centerIn: parent
                                        width: 25
                                        height: 25
                                        visible: row.iconSource !== ""
                                        sourceSize.width: width * Screen.devicePixelRatio
                                        sourceSize.height: height * Screen.devicePixelRatio
                                        source: row.iconSource
                                        fillMode: Image.PreserveAspectFit
                                        asynchronous: true
                                    }

                                    // Same fallback as the notification stack: a glyph, not an
                                    // empty tile. application-x-executable is missing from most
                                    // icon themes, so it left the well blank.
                                    Text {
                                        anchors.centerIn: parent
                                        visible: row.iconSource === ""
                                        text: "apps"
                                        color: row.selected ? "#d6d6d6" : "#9a9a9a"
                                        font.family: "Material Symbols Rounded"
                                        font.pixelSize: 22

                                        Behavior on color { ColorAnimation { duration: 110 } }
                                    }
                                }

                                Column {
                                    anchors.left: iconWell.right
                                    anchors.leftMargin: 12
                                    anchors.right: launchArrow.left
                                    anchors.rightMargin: 8
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: 3

                                    Text {
                                        width: parent.width
                                        text: row.modelData.name || "Application"
                                        color: "#f4f4f4"
                                        font.family: root.uiFont
                                        font.pixelSize: 15
                                        font.weight: Font.DemiBold
                                        elide: Text.ElideRight
                                    }

                                    Text {
                                        width: parent.width
                                        text: row.modelData.genericName || row.modelData.comment || ""
                                        visible: text.length > 0
                                        color: "#858585"
                                        font.family: root.detailFont
                                        font.pixelSize: 10
                                        elide: Text.ElideRight
                                    }
                                }

                                Text {
                                    id: launchArrow
                                    anchors.right: parent.right
                                    anchors.rightMargin: 16
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "↗"
                                    color: "#b8b8b8"
                                    font.family: root.detailFont
                                    font.pixelSize: 14
                                    opacity: row.selected ? 1 : 0
                                    scale: row.selected ? 1 : 0.75
                                    Behavior on opacity { NumberAnimation { duration: 120 } }
                                    Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutQuart } }
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onEntered: root.selectedIndex = row.index
                                    onClicked: root.launch(row.modelData)
                                }
                            }
                        }

                        Column {
                            anchors.centerIn: parent
                            visible: root.results.length === 0
                            spacing: 6
                            opacity: 0.45 + root.filterProgress * 0.55

                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: "search_off"
                                color: "#777777"
                                font.family: "Material Symbols Rounded"
                                font.pixelSize: 24
                            }

                            Text {
                                text: "No matching programs"
                                color: "#909090"
                                font.family: root.detailFont
                                font.pixelSize: 11
                            }
                        }
                    }

                    Item {
                        id: searchBox
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        height: root.searchHeight

                        Rectangle {
                            anchors.top: parent.top
                            anchors.left: parent.left
                            anchors.leftMargin: 16
                            anchors.right: parent.right
                            anchors.rightMargin: 16
                            height: 1
                            color: "#1d1d1d"
                        }

                        Rectangle {
                            id: searchPill
                            anchors.fill: parent
                            anchors.topMargin: 10
                            anchors.bottomMargin: 10
                            anchors.leftMargin: 16
                            anchors.rightMargin: 16
                            radius: 17
                            color: "#121212"
                            border.width: 1
                            border.color: searchInput.activeFocus ? "#555555" : "#292929"

                            Behavior on border.color { ColorAnimation { duration: 140 } }

                            Text {
                                id: searchIcon
                                anchors.left: parent.left
                                anchors.leftMargin: 14
                                anchors.verticalCenter: parent.verticalCenter
                                text: "search"
                                color: searchInput.activeFocus ? "#dedede" : "#747474"
                                font.family: "Material Symbols Rounded"
                                font.pixelSize: 20
                                Behavior on color { ColorAnimation { duration: 140 } }
                            }

                            Text {
                                anchors.left: searchIcon.right
                                anchors.leftMargin: 10
                                anchors.verticalCenter: parent.verticalCenter
                                text: "Search programs…"
                                visible: searchInput.text.length === 0
                                color: "#737373"
                                font.family: root.uiFont
                                font.pixelSize: 14
                            }

                            TextInput {
                                id: searchInput
                                anchors.left: searchIcon.right
                                anchors.leftMargin: 10
                                anchors.right: hint.left
                                anchors.rightMargin: 12
                                anchors.verticalCenter: parent.verticalCenter
                                text: root.query
                                color: "#f4f4f4"
                                selectionColor: "#3f3f3f"
                                selectedTextColor: "#ffffff"
                                font.family: root.uiFont
                                font.pixelSize: 14
                                font.weight: Font.Medium
                                clip: true
                                onTextChanged: if (root.query !== text) root.query = text

                                Keys.onPressed: function(event) {
                                    if (event.key === Qt.Key_Escape) {
                                        root.close()
                                        event.accepted = true
                                    } else if (event.key === Qt.Key_Up) {
                                        root.moveSelection(-1)
                                        event.accepted = true
                                    } else if (event.key === Qt.Key_Down) {
                                        root.moveSelection(1)
                                        event.accepted = true
                                    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                                        if (root.results.length > 0) root.launch(root.results[root.selectedIndex])
                                        event.accepted = true
                                    }
                                }
                            }

                            Rectangle {
                                id: hint
                                anchors.right: parent.right
                                anchors.rightMargin: 10
                                anchors.verticalCenter: parent.verticalCenter
                                width: 30
                                height: 26
                                radius: 9
                                color: "#202020"
                                border.width: 1
                                border.color: "#323232"

                                Text {
                                    anchors.centerIn: parent
                                    text: "↵"
                                    color: "#9a9a9a"
                                    font.family: root.detailFont
                                    font.pixelSize: 12
                                }
                            }
                        }
                    }
                }
            }
    }

    // Shared with Notifications.qml: quarter-circle cutout joining panel to frame.
    component Fillet: Shape {
        id: fillet
        readonly property int r: root.corner
        width: r
        height: r
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            strokeWidth: 0
            fillColor: root.frameColor
            PathSvg {
                path: "M 0 0 L " + fillet.r + " 0 L " + fillet.r + " " + fillet.r
                    + " A " + fillet.r + " " + fillet.r + " 0 0 0 0 0 Z"
            }
        }
    }

    Variants {
        model: Quickshell.screens
        LauncherPanel {}
    }
}
