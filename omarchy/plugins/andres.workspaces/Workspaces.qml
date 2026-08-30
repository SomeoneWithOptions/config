pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Widgets
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "omarchy.workspaces"

  readonly property bool transparentBar: root.bar && root.bar.transparent
  readonly property color adaptiveForeground: root.bar ? root.bar.barForeground : "#f2f0e8"
  readonly property color pill: root.transparentBar ? Util.alpha(root.adaptiveForeground, 0.14) : "#242528"
  readonly property color pillHover: root.transparentBar ? Util.alpha(root.adaptiveForeground, 0.22) : "#303135"
  readonly property color foreground: root.transparentBar ? root.adaptiveForeground : "#f2f0e8"
  readonly property color selected: root.transparentBar ? Util.alpha(root.adaptiveForeground, 0.30) : "#dedfe3"
  readonly property var monitor: {
    var window = root.QsWindow ? root.QsWindow.window : null
    return window ? Hyprland.monitorFor(window.screen) : Hyprland.focusedMonitor
  }
  readonly property var workspaceValues: Hyprland.workspaces.values
    .filter(function(workspace) { return workspace.monitor === root.monitor })
    .sort(root.workspaceOrder)

  function workspaceOrder(left, right) {
    if (left.id > 0 && right.id < 0) return -1
    if (left.id < 0 && right.id > 0) return 1
    return left.id > 0 ? left.id - right.id : left.name.localeCompare(right.name)
  }

  function appIcon(client) {
    var ipc = client && client.lastIpcObject ? client.lastIpcObject : {}
    var names = [
      client && client.wayland ? client.wayland.appId || "" : "",
      ipc.class || "",
      ipc.initialClass || ""
    ].filter(function(name) { return name.length > 0 })
    var entries = DesktopEntries.applications.values || []
    var entry = null

    for (var i = 0; i < names.length; i++) {
      var needle = names[i].replace(/\.desktop$/i, "").toLowerCase()
      entry = entries.find(function(app) {
        return app.id.toLowerCase() === needle || (app.startupClass || "").toLowerCase() === needle
      })
      if (entry) break
    }

    if (!entry && names.length > 0) entry = DesktopEntries.heuristicLookup(names[0])
    return Quickshell.iconPath(entry ? entry.icon || "" : "", "application-x-executable")
  }

  implicitWidth: workspaceRow.implicitWidth
  implicitHeight: root.barSize

  Row {
    id: workspaceRow
    anchors.verticalCenter: parent.verticalCenter
    spacing: Style.spacing.sm

    Repeater {
      model: ScriptModel { values: root.workspaceValues }

      WidgetButton {
        id: workspace
        required property var modelData
        readonly property bool isSelected: modelData.active

        bar: root.bar
        text: modelData.name
        labelVisible: false
        fixedWidth: Math.max(workspace.fixedHeight, workspaceContent.implicitWidth + Style.space(20))
        fixedHeight: Style.space(30)
        tooltipText: "Workspace " + modelData.name
        onPressed: function(button) {
          if (button === Qt.LeftButton) modelData.activate()
        }
        onWheelMoved: function(delta) {
          Hyprland.dispatch(delta > 0 ? "workspace r-1" : "workspace r+1")
        }

        Rectangle {
          anchors.fill: parent
          radius: height / 2
          antialiasing: true
          smooth: true
          color: workspaceHover.hovered
            ? (workspace.isSelected ? "#ececef" : root.pillHover)
            : (workspace.isSelected ? root.selected : root.pill)
          border.width: 1
          border.color: workspace.modelData.urgent
            ? "#c66b6b"
            : (root.transparentBar
              ? Util.alpha(root.adaptiveForeground, workspace.isSelected ? 0.50 : 0.24)
              : (workspace.isSelected ? "#f3f3f5" : "#35363a"))

          Behavior on color { ColorAnimation { duration: 180; easing.type: Easing.OutCubic } }
          Behavior on border.color { ColorAnimation { duration: 180; easing.type: Easing.OutCubic } }
        }

        Row {
          id: workspaceContent
          anchors.centerIn: parent
          spacing: apps.count > 0 ? 7 : 0

          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: workspace.modelData.name
            color: workspace.isSelected && !root.transparentBar ? "#151517" : root.foreground
            font.family: "DM Sans"
            font.pixelSize: Style.font.bodySmall
            font.weight: Font.DemiBold
            renderType: Text.NativeRendering

            Behavior on color { ColorAnimation { duration: 180; easing.type: Easing.OutCubic } }
          }

          ListView {
            id: apps
            readonly property real targetWidth: Math.min(contentWidth, 150)

            anchors.verticalCenter: parent.verticalCenter
            orientation: ListView.Horizontal
            width: count > 0 ? targetWidth : 0
            height: 24
            spacing: Style.spacing.xs
            clip: true
            interactive: false
            model: ScriptModel { values: workspace.modelData.toplevels.values }

            Behavior on width { NumberAnimation { duration: 240; easing.type: Easing.OutExpo } }
            add: Transition {
              NumberAnimation { property: "scale"; from: 0.72; to: 1; duration: 180; easing.type: Easing.OutCubic }
              NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 180; easing.type: Easing.OutCubic }
            }
            remove: Transition {
              NumberAnimation { properties: "opacity,scale"; from: 1; to: 0; duration: 140; easing.type: Easing.InCubic }
            }
            move: Transition {
              NumberAnimation { properties: "x,y"; duration: 200; easing.type: Easing.OutCubic }
            }

            delegate: WidgetButton {
              id: app
              required property var modelData

              bar: root.bar
              text: modelData.title || "Application"
              labelVisible: false
              fixedWidth: 22
              fixedHeight: 24
              tooltipText: modelData.title
              onPressed: function(button) {
                if (button === Qt.LeftButton)
                  Hyprland.dispatch("focuswindow address:" + modelData.address)
              }

              Rectangle {
                anchors.centerIn: parent
                width: 22
                height: 22
                radius: Style.space(6)
                antialiasing: true
                color: appHover.hovered
                  ? (root.transparentBar
                    ? Util.alpha(root.adaptiveForeground, 0.18)
                    : (workspace.isSelected ? "#c9cace" : "#393a3f"))
                  : "transparent"

                Behavior on color { ColorAnimation { duration: 150; easing.type: Easing.OutCubic } }

                IconImage {
                  anchors.centerIn: parent
                  width: 14
                  height: 14
                  source: root.appIcon(app.modelData)
                  asynchronous: false
                  smooth: true
                  mipmap: true
                }
              }

              HoverHandler { id: appHover }
            }
          }
        }

        HoverHandler { id: workspaceHover }
        Behavior on fixedWidth { NumberAnimation { duration: 190; easing.type: Easing.OutCubic } }
      }
    }
  }
}
