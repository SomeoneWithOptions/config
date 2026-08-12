pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Services.Notifications
import Quickshell.Wayland

Item {
    id: root

    property bool mounted: false
    property real reveal: 0
    property double now: Date.now()
    readonly property var items: server.trackedNotifications.values
    readonly property int count: items.length

    FrameStyle { id: style }

    // Drawer joins painted frame edges, not smaller reserved workspace edges.
    // This keeps full curves visible where it leaves top and right bars.
    readonly property int topOffset: style.drawerTop
    readonly property int frameBorder: style.edgeInset
    readonly property int corner: style.cornerRadius
    readonly property int cardsWidth: 400
    readonly property int pad: 10
    readonly property color frameColor: style.frameColor
    readonly property string uiFont: "DM Sans"
    readonly property string detailFont: "Azeret Mono"
    readonly property bool reduceMotion: Quickshell.env("DESKTOP_FRAME_REDUCED_MOTION") === "1"
    readonly property int slideDuration: reduceMotion ? 0 : 420
    readonly property bool silenced: dndFile.text().trim() === "1"

    function age(created) {
        var mins = Math.floor((now - created) / 60000)
        if (mins < 1) return "now"
        if (mins < 60) return mins + "m"
        var hours = Math.floor(mins / 60)
        if (hours < 24) return hours + "h"
        return Math.floor(hours / 24) + "d"
    }

    // notify-send routes both icon names and file paths through `image` as
    // image://icon/…, and that provider renders a broken-icon tile for names the
    // theme lacks. Resolve names ourselves so misses fall back to the glyph.
    function resolveIcon(name) {
        if (!name) return ""
        if (name.startsWith("image://icon/")) name = name.substring(13)
        else if (name.indexOf("://") >= 0) return name
        if (name.startsWith("/")) return "file://" + name
        return Quickshell.iconPath(name, true)
    }

    function defaultAction(notification) {
        var actions = notification.actions || []
        for (var i = 0; i < actions.length; i++)
            if (actions[i].identifier === "default") return actions[i]
        return null
    }

    function newest() {
        return count > 0 ? items[count - 1] : null
    }

    function dismissAll() {
        var open = items.slice()
        for (var i = 0; i < open.length; i++) open[i].dismiss()
    }

    onCountChanged: {
        if (count > 0) {
            closeTimer.stop()
            mounted = true
            reveal = 1
        } else {
            reveal = 0
            if (slideDuration === 0) mounted = false
            else closeTimer.restart()
        }
    }

    Behavior on reveal {
        NumberAnimation { duration: root.slideDuration; easing.type: Easing.OutExpo }
    }

    Timer {
        id: closeTimer
        interval: root.slideDuration
        onTriggered: root.mounted = false
    }

    // Relative timestamps only ever show whole minutes, so a coarse tick is enough.
    Timer {
        interval: 30000
        running: root.mounted
        repeat: true
        onTriggered: root.now = Date.now()
    }

    FileView {
        id: dndFile
        path: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state")
            + "/omarchy/notifications-silenced"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
    }

    NotificationServer {
        id: server
        keepOnReload: false
        actionsSupported: true
        bodySupported: true
        bodyMarkupSupported: true
        imageSupported: true

        onNotification: function(notification) {
            // Critical notifications ignore do-not-disturb, same as mako's default.
            if (root.silenced && notification.urgency !== NotificationUrgency.Critical) return
            notification.tracked = true
        }
    }

    IpcHandler {
        target: "notifications"
        function dismiss(): void { var n = root.newest(); if (n) n.dismiss() }
        function dismissAll(): void { root.dismissAll() }
        function invoke(): void {
            var n = root.newest()
            if (!n) return
            var action = root.defaultAction(n)
            if (action) action.invoke()
            else n.dismiss()
        }
    }

    component NotificationPanel: PanelWindow {
        id: panel
        required property var modelData
        readonly property bool focusedScreen: Hyprland.focusedMonitor
            ? Hyprland.focusedMonitor.name === modelData.name : true

        screen: modelData
        visible: root.mounted && focusedScreen
        color: "transparent"
        surfaceFormat.opaque: false
        exclusionMode: ExclusionMode.Ignore
        mask: Region { item: drawer }
        anchors { top: true; right: true; bottom: true; left: true }
        WlrLayershell.namespace: "andres-desktop-notifications"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

        // Grows with the cards, then the reveal factor slides the whole drawer
        // back up behind the top strip when the stack empties.
        property real contentHeight: list.contentHeight + root.pad * 2
        readonly property real shown: contentHeight * root.reveal
        readonly property int drawerLeft: width - root.frameBorder - root.cardsWidth - root.pad * 2

        Behavior on contentHeight {
            NumberAnimation { duration: root.reduceMotion ? 0 : 320; easing.type: Easing.OutExpo }
        }

        Item {
            id: drawer
            x: panel.drawerLeft
            y: root.topOffset
            width: panel.width - panel.drawerLeft
            height: panel.shown
            clip: true

            Rectangle {
                anchors.fill: parent
                color: root.frameColor
                bottomLeftRadius: root.corner
            }

            ListView {
                id: list
                x: root.pad
                width: root.cardsWidth
                // Anchored to the drawer's bottom edge so cards ride out with it.
                y: drawer.height - root.pad - list.contentHeight
                height: list.contentHeight
                model: root.items
                spacing: 6
                interactive: false
                verticalLayoutDirection: ListView.BottomToTop

                add: Transition {
                    NumberAnimation { property: "y"; from: -60; duration: root.reduceMotion ? 0 : 380; easing.type: Easing.OutExpo }
                    NumberAnimation { property: "opacity"; from: 0; to: 1; duration: root.reduceMotion ? 0 : 240 }
                }

                remove: Transition {
                    NumberAnimation { property: "opacity"; to: 0; duration: root.reduceMotion ? 0 : 180 }
                    NumberAnimation { property: "scale"; to: 0.94; duration: root.reduceMotion ? 0 : 180 }
                }

                displaced: Transition {
                    NumberAnimation { properties: "x,y"; duration: root.reduceMotion ? 0 : 300; easing.type: Easing.OutExpo }
                }

                delegate: Rectangle {
                    id: card
                    required property var modelData
                    property bool expanded: false
                    readonly property bool critical: modelData.urgency === NotificationUrgency.Critical
                    // expireTimeout comes straight off the wire in milliseconds.
                    // 0 means "never expire" per spec, so only <0 takes the default.
                    readonly property real timeoutMs: modelData.expireTimeout < 0
                        ? (critical ? 0 : 5000) : modelData.expireTimeout
                    readonly property double created: Date.now()
                    readonly property string iconSource: root.resolveIcon(modelData.image)
                        || root.resolveIcon(modelData.appIcon)
                    readonly property var extraActions: (modelData.actions || [])
                        .filter(function(a) { return a.identifier !== "default" })

                    width: ListView.view.width
                    height: layout.implicitHeight + 24
                    radius: root.corner
                    color: hover.containsMouse ? "#282828" : (critical ? "#2c2020" : "#1f1f1f")

                    Behavior on color { ColorAnimation { duration: 110 } }
                    Behavior on height {
                        NumberAnimation { duration: root.reduceMotion ? 0 : 260; easing.type: Easing.OutExpo }
                    }

                    Timer {
                        interval: Math.max(1, card.timeoutMs)
                        running: card.timeoutMs > 0 && !hover.containsMouse && !card.expanded
                        onTriggered: card.modelData.expire()
                    }

                    MouseArea {
                        id: hover
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                        onClicked: function(mouse) {
                            if (mouse.button === Qt.MiddleButton) {
                                card.modelData.dismiss()
                                return
                            }
                            var action = root.defaultAction(card.modelData)
                            if (action) action.invoke()
                            else card.modelData.dismiss()
                        }
                    }

                    Item {
                        id: iconWell
                        anchors.left: parent.left
                        anchors.leftMargin: 14
                        anchors.top: parent.top
                        anchors.topMargin: 12
                        width: 32
                        height: 32

                        Image {
                            anchors.fill: parent
                            visible: card.iconSource !== ""
                            source: card.iconSource
                            sourceSize.width: width * Screen.devicePixelRatio
                            sourceSize.height: height * Screen.devicePixelRatio
                            fillMode: Image.PreserveAspectFit
                            asynchronous: true
                        }

                        // Outline weight only: Qt renders this font's FILL=1 axis
                        // as garbled outlines, so no filled variant here.
                        Text {
                            anchors.centerIn: parent
                            visible: card.iconSource === ""
                            text: card.critical ? "error" : "info"
                            color: card.critical ? "#e8a0a0" : "#d6d6d6"
                            font.family: "Material Symbols Rounded"
                            font.pixelSize: 30
                        }
                    }

                    Column {
                        id: layout
                        anchors.left: iconWell.right
                        anchors.leftMargin: 12
                        anchors.right: chevron.left
                        anchors.rightMargin: 6
                        anchors.top: parent.top
                        anchors.topMargin: 12
                        spacing: 2

                        // Collapsed shows the summary; expanded promotes the app name
                        // to the header and gives the summary its own line.
                        Row {
                            width: parent.width
                            spacing: 6

                            Text {
                                text: card.expanded
                                    ? (card.modelData.appName || card.modelData.summary || "Notification")
                                    : (card.modelData.summary || card.modelData.appName || "Notification")
                                width: Math.min(implicitWidth, parent.width - 56)
                                color: card.expanded ? "#9d9d9d" : "#f4f4f4"
                                font.family: root.uiFont
                                font.pixelSize: card.expanded ? 12 : 15
                                font.weight: card.expanded ? Font.Medium : Font.DemiBold
                                elide: Text.ElideRight
                            }

                            Text {
                                text: "•"
                                color: "#5f5f5f"
                                font.family: root.uiFont
                                font.pixelSize: card.expanded ? 11 : 14
                            }

                            Text {
                                text: root.age(card.created)
                                color: "#858585"
                                font.family: root.detailFont
                                font.pixelSize: card.expanded ? 10 : 11
                            }
                        }

                        Text {
                            width: parent.width
                            visible: card.expanded
                            text: card.modelData.summary || ""
                            color: "#f4f4f4"
                            font.family: root.uiFont
                            font.pixelSize: 15
                            font.weight: Font.DemiBold
                            elide: Text.ElideRight
                        }

                        Text {
                            id: bodyText
                            width: parent.width
                            visible: text.length > 0
                            text: card.modelData.body
                            textFormat: Text.StyledText
                            color: "#adadad"
                            font.family: root.uiFont
                            font.pixelSize: 13
                            elide: card.expanded ? Text.ElideNone : Text.ElideRight
                            wrapMode: card.expanded ? Text.Wrap : Text.NoWrap
                            maximumLineCount: card.expanded ? 8 : 1
                            onLinkActivated: function(link) { Qt.openUrlExternally(link) }
                        }

                        Row {
                            spacing: 6
                            visible: card.expanded && card.extraActions.length > 0
                            topPadding: 4

                            Repeater {
                                model: card.extraActions

                                Rectangle {
                                    id: actionPill
                                    required property var modelData
                                    width: actionLabel.implicitWidth + 22
                                    height: 28
                                    radius: 10
                                    color: actionHover.containsMouse ? "#333333" : "#242424"
                                    border.width: 1
                                    border.color: "#343434"

                                    Behavior on color { ColorAnimation { duration: 110 } }

                                    Text {
                                        id: actionLabel
                                        anchors.centerIn: parent
                                        text: actionPill.modelData.text
                                        color: "#e0e0e0"
                                        font.family: root.uiFont
                                        font.pixelSize: 12
                                        font.weight: Font.Medium
                                    }

                                    MouseArea {
                                        id: actionHover
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: actionPill.modelData.invoke()
                                    }
                                }
                            }
                        }
                    }

                    Text {
                        id: chevron
                        anchors.right: parent.right
                        anchors.rightMargin: 14
                        anchors.top: parent.top
                        anchors.topMargin: 18
                        visible: bodyText.truncated || card.extraActions.length > 0 || card.expanded
                        text: "expand_more"
                        color: chevronHover.containsMouse ? "#e8e8e8" : "#9a9a9a"
                        font.family: "Material Symbols Rounded"
                        font.pixelSize: 20
                        rotation: card.expanded ? 180 : 0

                        Behavior on rotation { NumberAnimation { duration: 180; easing.type: Easing.OutQuart } }
                        Behavior on color { ColorAnimation { duration: 110 } }

                        MouseArea {
                            id: chevronHover
                            anchors.centerIn: parent
                            width: 32
                            height: 32
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: card.expanded = !card.expanded
                        }
                    }
                }
            }
        }

        // Concave fillets: same trick FrameService uses for the frame's inner
        // corners, so the drawer reads as a bulge in the black rather than a card
        // parked next to it. One where it leaves the top strip, one where its
        // bottom edge runs into the right border.
        Item {
            x: drawer.x - root.corner
            y: drawer.y
            width: root.corner
            height: Math.min(root.corner, drawer.height)
            clip: true
            Fillet {}
        }

        Fillet {
            x: panel.width - root.frameBorder - root.corner
            y: drawer.y + drawer.height
        }
    }

    component Fillet: FrameJoin {}

    Variants {
        model: Quickshell.screens
        NotificationPanel {}
    }
}
