pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Bluetooth
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Services.Pipewire
import Quickshell.Services.SystemTray
import Quickshell.Services.UPower
import Quickshell.Wayland
import Quickshell.Widgets

Item {
    id: root

    property bool enabled: true
    property bool shown: true

    FrameStyle { id: style }

    readonly property color background: "#000000"
    readonly property color pill: "#242528"
    readonly property color pillHover: "#303135"
    readonly property color foreground: "#f2f0e8"
    readonly property color muted: "#a6a6a8"
    readonly property color active: "#dedfe3"
    readonly property int barHeight: style.topBarHeight
    property string networkKind: "disconnected"
    property int networkSignal: 0
    property string networkConnection: ""

    function launch(command) {
        Quickshell.execDetached(["sh", "-lc", command])
    }

    function workspaceOrder(a, b) {
        if (a.id > 0 && b.id < 0) return -1
        if (a.id < 0 && b.id > 0) return 1
        return a.id > 0 ? a.id - b.id : a.name.localeCompare(b.name)
    }

    function appIcon(client) {
        const ipc = client?.lastIpcObject ?? {}
        // wayland.appId is set the moment the window maps. lastIpcObject stays
        // empty until a toplevel IPC refresh that never comes, so windows opened
        // after startup fell through to the generic icon.
        const names = [client?.wayland?.appId ?? "", ipc.class ?? "", ipc.initialClass ?? ""]
            .filter(name => name.length > 0)
        const entries = DesktopEntries.applications.values ?? []
        let entry = null

        // Exact desktop ID/StartupWMClass must win. Quickshell's fuzzy lookup
        // mistakes org.gnome.Nautilus for Avahi and returns network-wired.
        for (const name of names) {
            const needle = name.replace(/\.desktop$/i, "").toLowerCase()
            entry = entries.find(app => app.id.toLowerCase() === needle
                || (app.startupClass ?? "").toLowerCase() === needle)
            if (entry) break
        }
        if (!entry && names.length > 0) entry = DesktopEntries.heuristicLookup(names[0])
        return Quickshell.iconPath(entry?.icon ?? "", "application-x-executable")
    }

    function materialText(markup) {
        const match = (markup ?? "").match(/>([^<]+)<\/span>/)
        return match ? match[1].trim() : (markup ?? "").trim()
    }

    IpcHandler {
        target: "topBar"
        function toggle(): void { root.shown = !root.shown }
        function show(): void { root.shown = true }
        function hide(): void { root.shown = false }
    }

    PwObjectTracker {
        objects: Pipewire.defaultAudioSink ? [Pipewire.defaultAudioSink] : []
    }

    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }

    Process {
        id: networkProcess
        command: ["sh", "-c", "iface=$(iw dev 2>/dev/null | awk '$1==\"Interface\"{print $2; exit}'); if [ -n \"$iface\" ]; then link=$(iw dev \"$iface\" link 2>/dev/null); if printf '%s' \"$link\" | grep -q '^Connected'; then signal=$(printf '%s\\n' \"$link\" | awk '/signal:/{print int($2); exit}'); ssid=$(printf '%s\\n' \"$link\" | sed -n 's/^\\s*SSID: //p' | head -1); printf 'wifi\\t%s\\t%s\\n' \"$signal\" \"$ssid\"; exit; fi; fi; iface=$(ip route show default 2>/dev/null | awk '{print $5; exit}'); if [ -n \"$iface\" ]; then printf 'ethernet\\t0\\t%s\\n' \"$iface\"; else printf 'disconnected\\t0\\t\\n'; fi"]
        stdout: StdioCollector {
            onStreamFinished: {
                const parts = text.trim().split("\t")
                root.networkKind = parts[0] ?? "disconnected"
                root.networkSignal = parseInt(parts[1] ?? "0", 10)
                root.networkConnection = parts[2] ?? ""
            }
        }
    }

    Timer {
        interval: 3000
        repeat: true
        running: root.enabled
        triggeredOnStart: true
        onTriggered: if (!networkProcess.running) networkProcess.running = true
    }

    Variants {
        model: root.enabled ? Quickshell.screens : []

        PanelWindow {
            id: bar
            required property var modelData
            readonly property var monitor: Hyprland.monitorFor(modelData)
            readonly property bool fullscreen: monitor?.activeWorkspace?.hasFullscreen ?? false
            readonly property var workspaceValues: Hyprland.workspaces.values
                .filter(workspace => workspace.monitor === monitor)
                .sort(root.workspaceOrder)

            screen: modelData
            visible: root.shown && !fullscreen
            color: root.background
            implicitHeight: root.barHeight
            exclusiveZone: visible ? root.barHeight : 0
            anchors { top: true; left: true; right: true }
            WlrLayershell.namespace: "andres-quickshell-topbar"
            WlrLayershell.layer: WlrLayer.Top
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

            Row {
                id: workspaceRow
                anchors.left: parent.left
                anchors.leftMargin: style.edgeInset + 5
                anchors.verticalCenter: parent.verticalCenter
                spacing: 9

                Repeater {
                    model: ScriptModel { values: bar.workspaceValues }

                    Rectangle {
                        id: workspace
                        required property var modelData
                        readonly property bool selected: modelData.active

                        // Empty workspace collapses to a circle (radius == height / 2).
                        width: Math.max(height, workspaceContent.implicitWidth + 20)
                        height: 32
                        radius: 16
                        color: workspaceMouse.containsMouse
                            ? (selected ? "#ececef" : root.pillHover)
                            : (selected ? root.active : root.pill)
                        border.width: 1
                        border.color: modelData.urgent ? "#c66b6b" : (selected ? "#f3f3f5" : "#35363a")
                        clip: true

                        Behavior on width { NumberAnimation { duration: 190; easing.type: Easing.OutCubic } }
                        Behavior on color { ColorAnimation { duration: 150 } }

                        Row {
                            id: workspaceContent
                            z: 1
                            anchors.centerIn: parent
                            spacing: apps.count > 0 ? 7 : 0

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: workspace.modelData.name
                                color: workspace.selected ? "#151517" : root.foreground
                                font.family: "DM Sans"
                                font.pixelSize: 12
                                font.weight: Font.DemiBold

                                Behavior on color { ColorAnimation { duration: 150 } }
                            }

                            ListView {
                                id: apps
                                readonly property real targetWidth: Math.min(contentWidth, 150)

                                anchors.verticalCenter: parent.verticalCenter
                                orientation: ListView.Horizontal
                                width: count > 0 ? targetWidth : 0
                                height: 24
                                spacing: 4
                                clip: true
                                interactive: false
                                model: ScriptModel { values: workspace.modelData.toplevels.values }

                                Behavior on width { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                                add: Transition {
                                    NumberAnimation { property: "scale"; from: 0.72; to: 1; duration: 160; easing.type: Easing.OutCubic }
                                }
                                remove: Transition {
                                    NumberAnimation { properties: "opacity,scale"; from: 1; to: 0; duration: 150; easing.type: Easing.InCubic }
                                }
                                move: Transition {
                                    NumberAnimation { properties: "x,y"; duration: 180; easing.type: Easing.OutCubic }
                                }

                                delegate: MouseArea {
                                    id: appMouse
                                    required property var modelData
                                    width: 22
                                    height: 24
                                    hoverEnabled: true
                                    onClicked: Hyprland.dispatch("focuswindow address:" + modelData.address)
                                    Controls.ToolTip.visible: containsMouse
                                    Controls.ToolTip.text: modelData.title
                                    Controls.ToolTip.delay: 450

                                    Rectangle {
                                        anchors.centerIn: parent
                                        width: 22
                                        height: 22
                                        radius: 6
                                        color: appMouse.containsMouse
                                            ? (workspace.selected ? "#c9cace" : "#393a3f")
                                            : "transparent"

                                        Behavior on color { ColorAnimation { duration: 120 } }

                                        IconImage {
                                            anchors.centerIn: parent
                                            width: 17
                                            height: 17
                                            source: root.appIcon(appMouse.modelData)
                                            asynchronous: false
                                        }
                                    }
                                }
                            }
                        }

                        MouseArea {
                            id: workspaceMouse
                            anchors.fill: parent
                            z: 0
                            hoverEnabled: true
                            onClicked: workspace.modelData.activate()
                            onWheel: event => Hyprland.dispatch(event.angleDelta.y > 0 ? "workspace r-1" : "workspace r+1")
                        }
                    }
                }
            }

            Row {
                id: rightSide
                anchors.right: parent.right
                anchors.rightMargin: style.edgeInset + 5
                anchors.verticalCenter: parent.verticalCenter
                spacing: 9

                Rectangle {
                    id: trayPill
                    visible: trayItems.count > 0
                    width: visible ? trayRow.implicitWidth + 16 : 0
                    height: 32
                    radius: 16
                    color: root.pill
                    border.width: 1
                    border.color: "#35363a"

                    Row {
                        id: trayRow
                        anchors.centerIn: parent
                        spacing: 7

                        Repeater {
                            id: trayItems
                            model: ScriptModel { values: SystemTray.items.values }

                            MouseArea {
                                required property SystemTrayItem modelData
                                width: 18
                                height: 20
                                hoverEnabled: true
                                acceptedButtons: Qt.LeftButton | Qt.RightButton
                                onClicked: event => event.button === Qt.LeftButton
                                    ? modelData.activate() : modelData.secondaryActivate()
                                Controls.ToolTip.visible: containsMouse
                                Controls.ToolTip.text: modelData.tooltipTitle || modelData.title
                                Controls.ToolTip.delay: 450

                                IconImage {
                                    anchors.centerIn: parent
                                    width: 15
                                    height: 15
                                    source: parent.modelData.icon
                                }
                            }
                        }
                    }
                }

                Rectangle {
                    width: statusRow.implicitWidth + 12
                    height: 32
                    radius: 16
                    color: root.pill
                    border.width: 1
                    border.color: "#35363a"

                    Row {
                        id: statusRow
                        anchors.centerIn: parent
                        spacing: 1

                        GlyphButton {
                            glyph: "system_update_alt"
                            tooltip: "Omarchy update"
                            onActivated: root.launch("omarchy-launch-floating-terminal-with-presentation omarchy-update")
                        }

                        CommandIndicator {
                            command: ["omarchy-voxtype-status"]
                            interval: 1000
                            iconFor: data => ({ idle: "mic", recording: "graphic_eq", transcribing: "speech_to_text" })[data.alt] ?? "mic"
                            onActivated: button => root.launch(button === Qt.RightButton ? "omarchy-voxtype-config" : "omarchy-voxtype-model")
                        }

                        CommandIndicator {
                            command: ["sh", "-c", "if pgrep -f '^gpu-screen-recorder' >/dev/null; then printf '%s\\n' '{\"text\":\"videocam\",\"tooltip\":\"Stop recording\",\"class\":\"active\"}'; else printf '%s\\n' '{\"text\":\"\"}'; fi"]
                            interval: 1000
                            onActivated: root.launch("omarchy-capture-screenrecording")
                        }

                        CommandIndicator {
                            command: ["sh", "-c", "if pgrep -x hypridle >/dev/null; then printf '%s\\n' '{\"text\":\"\"}'; else printf '%s\\n' '{\"text\":\"bedtime_off\",\"tooltip\":\"Idle lock disabled\",\"class\":\"active\"}'; fi"]
                            interval: 2000
                            onActivated: root.launch("omarchy-toggle-idle")
                        }

                        CommandIndicator {
                            command: ["sh", "-c", "if [ \"$(cat \"$HOME/.local/state/omarchy/notifications-silenced\" 2>/dev/null)\" = 1 ]; then printf '%s\\n' '{\"text\":\"notifications_off\",\"tooltip\":\"Notifications silenced\",\"class\":\"active\"}'; else printf '%s\\n' '{\"text\":\"\"}'; fi"]
                            interval: 1000
                            onActivated: root.launch(Quickshell.env("HOME") + "/.local/bin/omarchy-frame notify dnd")
                        }

                        GlyphButton {
                            glyph: Bluetooth.defaultAdapter === null ? "" : !Bluetooth.defaultAdapter.enabled ? "bluetooth_disabled"
                                : Bluetooth.devices.values.some(device => device.connected) ? "bluetooth_connected" : "bluetooth"
                            tooltip: Bluetooth.devices.values.filter(device => device.connected).map(device => device.name).join(", ") || "Bluetooth"
                            onActivated: root.launch("omarchy-launch-bluetooth")
                        }

                        GlyphButton {
                            glyph: root.networkKind === "ethernet" ? "lan" : root.networkKind !== "wifi" ? "wifi_off"
                                : root.networkSignal >= -52 ? "wifi" : root.networkSignal >= -67 ? "wifi_2_bar" : "wifi_1_bar"
                            tooltip: root.networkConnection || "Disconnected"
                            onActivated: root.launch("omarchy-launch-wifi")
                        }

                        GlyphButton {
                            readonly property var sink: Pipewire.defaultAudioSink
                            readonly property real volume: sink?.audio?.volume ?? 0
                            readonly property bool mutedAudio: sink?.audio?.muted ?? false
                            glyph: mutedAudio ? "volume_off" : volume <= 0.01 ? "volume_mute" : volume < 0.5 ? "volume_down" : "volume_up"
                            tooltip: mutedAudio ? "Muted" : "Playing at " + Math.round(volume * 100) + "%"
                            onActivated: button => {
                                if (button === Qt.RightButton && sink?.audio) sink.audio.muted = !sink.audio.muted
                                else root.launch("omarchy-launch-audio")
                            }
                            onScrolled: delta => {
                                if (!sink?.audio) return
                                sink.audio.muted = false
                                sink.audio.volume = Math.max(0, Math.min(1, volume + (delta > 0 ? 0.05 : -0.05)))
                            }
                        }

                        GlyphButton {
                            readonly property int percent: Math.round(UPower.displayDevice.percentage * 100)
                            readonly property bool charging: !UPower.onBattery
                            glyph: charging ? "battery_android_frame_bolt" : percent >= 95 ? "battery_android_full"
                                : percent >= 80 ? "battery_android_6" : percent >= 65 ? "battery_android_5"
                                : percent >= 50 ? "battery_android_4" : percent >= 35 ? "battery_android_3"
                                : percent >= 20 ? "battery_android_2" : percent >= 10 ? "battery_android_1" : "battery_android_0"
                            label: percent + "%"
                            tooltip: PowerProfile.toString(PowerProfiles.profile) + " • " + percent + "%"
                            alert: percent <= 15 && UPower.onBattery
                            onActivated: button => root.launch(button === Qt.RightButton
                                ? "notify-send -u low \"$(omarchy-battery-status)\"" : "omarchy-menu power")
                        }
                    }
                }

                Rectangle {
                    width: timeText.implicitWidth + 22
                    height: 32
                    radius: 16
                    color: root.pill
                    border.width: 1
                    border.color: "#35363a"

                    Text {
                        id: timeText
                        anchors.centerIn: parent
                        text: Qt.formatDateTime(clock.date, "ddd HH:mm")
                        color: root.foreground
                        font.family: "DM Sans"
                        font.pixelSize: 12
                        font.weight: Font.DemiBold
                    }

                    MouseArea {
                        anchors.fill: parent
                        acceptedButtons: Qt.RightButton
                        onClicked: root.launch("omarchy-launch-floating-terminal-with-presentation omarchy-tz-select")
                    }
                }
            }
        }
    }

    component GlyphButton: Item {
        id: button

        required property string glyph
        property string label: ""
        property string tooltip: ""
        property bool alert: false
        signal activated(int button)
        signal scrolled(real delta)

        visible: glyph.length > 0
        width: visible ? buttonContent.implicitWidth + 8 : 0
        height: 26

        Rectangle {
            anchors.fill: parent
            radius: 13
            color: buttonMouse.containsMouse ? root.pillHover : "transparent"
            Behavior on color { ColorAnimation { duration: 120 } }
        }

        Row {
            id: buttonContent
            anchors.centerIn: parent
            spacing: button.label.length > 0 ? 3 : 0

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: button.glyph
                color: button.alert ? "#d78383" : root.foreground
                font.family: "Material Symbols Rounded"
                font.pixelSize: 15
                font.variableAxes: ({ "FILL": 1 })
            }

            Text {
                visible: button.label.length > 0
                anchors.verticalCenter: parent.verticalCenter
                text: button.label
                color: button.alert ? "#d78383" : root.foreground
                font.family: "DM Sans"
                font.pixelSize: 11
                font.weight: Font.DemiBold
            }
        }

        MouseArea {
            id: buttonMouse
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onClicked: event => button.activated(event.button)
            onWheel: event => button.scrolled(event.angleDelta.y)
            Controls.ToolTip.visible: containsMouse && button.tooltip.length > 0
            Controls.ToolTip.text: button.tooltip
            Controls.ToolTip.delay: 450
        }
    }

    component CommandIndicator: GlyphButton {
        id: indicator

        property var command: []
        property int interval: 2000
        property var iconFor: null

        glyph: ""

        Process {
            id: process
            command: indicator.command
            stdout: StdioCollector {
                onStreamFinished: {
                    try {
                        const data = JSON.parse(text)
                        indicator.glyph = indicator.iconFor ? indicator.iconFor(data) : root.materialText(data.text)
                        indicator.tooltip = data.tooltip ?? ""
                        indicator.alert = data.class === "active" || data.alt === "recording"
                    } catch (error) {
                        indicator.glyph = ""
                    }
                }
            }
        }

        Timer {
            interval: indicator.interval
            repeat: true
            running: root.enabled && indicator.command.length > 0
            triggeredOnStart: true
            onTriggered: if (!process.running) process.running = true
        }
    }
}
