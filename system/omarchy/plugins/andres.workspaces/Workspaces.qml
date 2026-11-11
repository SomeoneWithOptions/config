pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "omarchy.workspaces"

  readonly property bool transparentBar: !!root.bar && root.bar.transparent === true
  readonly property color adaptiveForeground: root.bar ? root.bar.barForeground : "#f2f0e8"
  readonly property color pill: root.transparentBar ? Util.alpha(root.adaptiveForeground, 0.14) : "#242528"
  readonly property color pillHover: root.transparentBar ? Util.alpha(root.adaptiveForeground, 0.22) : "#303135"
  readonly property color foreground: root.transparentBar ? root.adaptiveForeground : "#f2f0e8"
  readonly property color selected: root.transparentBar ? Util.alpha(root.adaptiveForeground, 0.30) : "#dedfe3"

  // Workspaces are global 1-10 shared by every monitor (hypr/workspaces.lua
  // turns off 4.5's per-monitor blocks), so every bar uses block 0. The block
  // math stays so stock per-monitor behavior is one line away.
  readonly property int slots: 10

  readonly property var monitor: {
    var window = root.QsWindow.window
    var screen = window ? window.screen : null
    return screen ? Hyprland.monitorFor(screen) : Hyprland.focusedMonitor
  }
  readonly property string monitorName: root.monitor ? root.monitor.name : ""

  function blockOf(id) {
    return Math.floor((id - 1) / root.slots)
  }

  function slotOf(id) {
    return (id - 1) % root.slots + 1
  }

  function activeWorkspaceId() {
    return root.monitor && root.monitor.activeWorkspace ? root.monitor.activeWorkspace.id : -1
  }

  readonly property int block: 0

  function workspaceById(id) {
    var values = Hyprland.workspaces.values
    for (var i = 0; i < values.length; i++) {
      if (values[i].id === id) return values[i]
    }

    return null
  }

  // The first five of the monitor's own, and any of the rest that exist. After
  // them come workspaces that are only visiting: those of a monitor that is
  // unplugged, which had no room to join this one's.
  function workspaceIds() {
    var base = root.block * root.slots
    var ids = [base + 1, base + 2, base + 3, base + 4, base + 5]
    var guests = []
    var values = Hyprland.workspaces.values

    for (var i = 0; i < values.length; i++) {
      var id = values[i].id
      if (id <= 0) continue
      if (root.blockOf(id) === root.block) {
        if (ids.indexOf(id) === -1) ids.push(id)
      } else if (values[i].monitor && values[i].monitor.name === root.monitorName) {
        guests.push(id)
      }
    }

    ids.sort(function(left, right) { return left - right })
    guests.sort(function(left, right) { return left - right })
    return ids.concat(guests)
  }

  function dispatch(expression) {
    if (root.bar) root.bar.run("hyprctl dispatch " + Util.shellQuote(expression))
  }

  function focusWorkspace(id, name) {
    if (id < 0) {
      root.dispatch("hl.dsp.focus({ workspace = \"name:" + name + "\" })")
    } else if (root.blockOf(id) === root.block) {
      root.dispatch("o.workspaces.focus(" + root.slotOf(id) + ", \"" + root.monitorName + "\")")
    } else {
      root.dispatch("hl.dsp.focus({ workspace = \"" + id + "\" })")
    }
  }

  // A wheel notch moves one entry along the row, and a touchpad adds up its
  // smaller deltas until they make a notch's worth.
  property real wheelAccumulator: 0

  function scrollWorkspaces(delta) {
    var wheel = Util.wheelSteps(root.wheelAccumulator, delta)
    root.wheelAccumulator = wheel.remainder
    if (wheel.steps === 0) return

    // Holds at either end rather than wrapping, so a touchpad swipe that runs
    // long stops on the last workspace.
    var ids = root.workspaceIds()
    var index = ids.indexOf(root.activeWorkspaceId())
    if (index === -1) return
    var target = ids[Util.clamp(index - wheel.steps, 0, ids.length - 1)]
    if (target !== ids[index]) root.focusWorkspace(target)
  }

  // The workspace each monitor shows carries its layout: a square tiles, a
  // circle scrolls, and a triangle floats. Clicking it cycles to the next one,
  // as Super + L does.
  property string activeMode: "dwindle"
  property bool modeStale: false

  function modeGlyph(mode) {
    if (mode === "scrolling") return "󰝥"
    if (mode === "floating") return "󰔶"
    return "󱓻"
  }

  // A layout only changes through the layout commands, which ask for a refresh,
  // or a config reload, so each workspace's mode is read once and cached rather
  // than running the script on every workspace switch.
  property var modeCache: ({})
  property int modeGeneration: 0
  property int modeProcWorkspace: -1
  property int modeProcGeneration: 0

  function showActiveMode() {
    var mode = root.modeCache[root.activeWorkspaceId()]
    if (mode !== undefined) root.activeMode = mode
    else readMode()
  }

  function readMode() {
    if (modeProc.running) {
      root.modeStale = true
      return
    }
    var id = root.activeWorkspaceId()
    if (id === -1) return
    root.modeProcWorkspace = id
    root.modeProcGeneration = root.modeGeneration
    modeProc.command = ["omarchy-hyprland-workspace-layout-current", String(id)]
    modeProc.running = true
  }

  function refresh() {
    root.modeCache = ({})
    root.modeGeneration++
    readMode()
  }

  // The layout commands act on the focused workspace, so a click on another
  // monitor's bar focuses that monitor first.
  function cycleLayout() {
    if (!root.bar) return
    var command = "omarchy-hyprland-workspace-layout-toggle"
    if (root.monitor && !root.monitor.focused) {
      command = "hyprctl dispatch " + Util.shellQuote("hl.dsp.focus({ monitor = \"" + root.monitorName + "\" })") + " >/dev/null && " + command
    }
    root.bar.run(command)
  }

  Component.onCompleted: refresh()
  onMonitorChanged: root.showActiveMode()

  Connections {
    target: root.monitor
    function onActiveWorkspaceChanged() { root.showActiveMode() }
  }

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      var name = event ? String(event.name) : ""
      if (name === "configreloaded") root.refresh()
      // Quickshell credits every workspace switch to the focused monitor, as
      // the event doesn't say which one switched, and misses the workspace a
      // monitor falls back to when its own is moved away. Moving workspaces
      // between monitors switches the others, so ask Hyprland for the truth.
      // A workspace that changes number is only learned by asking too. Every
      // bar shares what Hyprland answers, so one asks after a plain switch.
      var switched = name === "workspacev2" && root.monitor !== null && root.monitor.focused
      if (switched || name === "moveworkspacev2" || name === "changeworkspaceid") {
        Hyprland.refreshMonitors()
        Hyprland.refreshWorkspaces()
      }
    }
  }

  Process {
    id: modeProc
    stdout: StdioCollector {
      onStreamFinished: {
        var mode = text.trim()
        // A read that started before a refresh may predate the change.
        if (!mode || root.modeProcGeneration !== root.modeGeneration) return
        root.modeCache[root.modeProcWorkspace] = mode
        if (root.modeProcWorkspace === root.activeWorkspaceId()) root.activeMode = mode
      }
    }
    onExited: {
      if (!root.modeStale) return
      root.modeStale = false
      // Deferred: the process still reports running while it signals exit.
      Qt.callLater(root.showActiveMode)
    }
  }

  // Super + L and the default layout change the mode without a focus change,
  // so they ask every bar to read it again.
  ShellIpc {
    target: "omarchy.workspaces"

    function refresh(): void { root.broadcast("refresh") }
  }


  // ------------------------------------------------------------ pixel grid
  // The panel runs at fractional scale (1.2 here), so any logical size whose
  // physical size is not a whole number lands a texture between device pixels
  // and the compositor blurs it. Every geometry value below is snapped to
  // whole device pixels, and insets are used instead of sizes so that centred
  // children keep an identical whole-pixel gap on both sides.
  readonly property real dpr: Screen.devicePixelRatio
  readonly property real px: 1 / root.dpr

  function dp(value) {
    return Math.round(value * root.dpr) * root.px
  }

  // Widen `inner` to an outer box that can hold it centred without a half
  // pixel: the total gap has to be even in device pixels.
  function centredOuter(inner, minOuter, padPerSide) {
    var outer = Math.max(minOuter, inner + 2 * padPerSide)
    var gap = Math.round((outer - inner) * root.dpr)
    if (gap % 2 !== 0) gap += 1
    return inner + gap * root.px
  }

  // Same rule from the other side: shrink a target size to the largest one
  // that still centres inside `outer` on whole device pixels.
  function centredInner(outer, target) {
    var gap = Math.round((outer - Math.min(target, outer)) * root.dpr)
    if (gap % 2 !== 0) gap += 1
    return outer - gap * root.px
  }

  readonly property real pillHeight: root.dp(Style.space(30))
  readonly property real pillPadding: root.dp(Style.space(10))
  readonly property real hairline: root.px
  readonly property real iconBoxInset: root.dp(Style.space(5))
  readonly property real iconBox: root.pillHeight - 2 * root.iconBoxInset
  // App icon size. 18 fills the box but leaves the hover square no visible
  // margin, so this sits one step below it. Snapped so the icon still centres
  // in its box on whole device pixels.
  readonly property real iconTargetSize: Style.space(17)
  readonly property real iconSize: root.centredInner(root.iconBox, root.iconTargetSize)
  readonly property real labelGap: root.dp(Style.space(5))
  readonly property real iconGap: root.dp(Style.space(3))
  readonly property real appsMaxWidth: root.dp(Style.space(150))

  // ---------------------------------------------------------- icon quality
  // `image://icon/` resolves against the icon theme at whatever sourceSize is
  // asked for, so requesting the display size hands back the 16x16 PNG for
  // apps that ship rasters (zen-browser, most Electron apps) and it then gets
  // upscaled by the device pixel ratio. Ask for the next standard theme size
  // at or above 2x physical instead and let the GPU mipmap down.
  readonly property var iconSizes: [16, 22, 24, 32, 48, 64, 128, 256, 512]

  function iconDecodeSize(displaySize) {
    var wanted = displaySize * root.dpr * 2
    for (var i = 0; i < root.iconSizes.length; i++) {
      if (root.iconSizes[i] >= wanted) return root.iconSizes[i]
    }
    return root.iconSizes[root.iconSizes.length - 1]
  }

  // Colour is reserved for the focused workspace; the rest read as chrome.
  readonly property real inactiveIconSaturation: -0.35
  readonly property real inactiveIconOpacity: 0.92

  readonly property var workspaceValues: Hyprland.workspaces.values
    .filter(function(workspace) {
      // Named workspaces (Super + F/C/S) have negative ids; keep them on the
      // monitor showing them. Special (scratchpad) ones stay hidden.
      if (workspace.id < 0) return !String(workspace.name).startsWith("special:") && workspace.monitor && workspace.monitor.name === root.monitorName
      return root.blockOf(workspace.id) === root.block || (workspace.monitor && workspace.monitor.name === root.monitorName)
    })
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
    spacing: root.dp(Style.spacing.sm)

    Repeater {
      model: ScriptModel { values: root.workspaceValues }

      WidgetButton {
        id: workspace
        required property var modelData
        readonly property bool isSelected: modelData.id === root.activeWorkspaceId()
        readonly property real contentWidth: root.dp(workspaceContent.implicitWidth)

        bar: root.bar
        text: modelData.name
        labelVisible: false
        fixedWidth: root.centredOuter(workspace.contentWidth, root.pillHeight, root.pillPadding)
        fixedHeight: root.pillHeight
        tooltipText: "Workspace " + modelData.name
        onPressed: function(button) {
          if (button === Qt.LeftButton) {
            if (workspace.isSelected) root.cycleLayout()
            else root.focusWorkspace(modelData.id, modelData.name)
          }
        }
        onWheelMoved: function(delta) {
          root.scrollWorkspaces(delta)
        }

        Rectangle {
          anchors.fill: parent
          radius: height / 2
          antialiasing: true
          smooth: true
          color: workspaceHover.hovered
            ? (workspace.isSelected ? "#ececef" : root.pillHover)
            : (workspace.isSelected ? root.selected : root.pill)
          // One device pixel, not one logical pixel: a 1.2px ring smears
          // across two rows of pixels and reads as a soft grey halo.
          border.width: root.hairline
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
          height: root.iconBox
          spacing: apps.count > 0 ? root.labelGap : 0

          Text {
            // Fixed box height so the baseline is solved against whole device
            // pixels; NativeRendering hints to the pixel grid and only pays
            // off if the glyph origin is actually on it.
            width: root.dp(implicitWidth)
            height: root.iconBox
            verticalAlignment: Text.AlignVCenter
            text: workspace.modelData.id < 0 ? String(workspace.modelData.name) : String(root.slotOf(workspace.modelData.id))
            color: workspace.isSelected && !root.transparentBar ? "#151517" : root.foreground
            font.family: "DM Sans"
            font.pixelSize: Style.font.bodySmall
            font.weight: Font.DemiBold
            renderType: Text.NativeRendering

            Behavior on color { ColorAnimation { duration: 180; easing.type: Easing.OutCubic } }
          }

          ListView {
            id: apps
            readonly property real targetWidth: Math.min(contentWidth, root.appsMaxWidth)

            anchors.verticalCenter: parent.verticalCenter
            orientation: ListView.Horizontal
            width: count > 0 ? targetWidth : 0
            height: root.iconBox
            spacing: root.iconGap
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
              fixedWidth: root.iconBox
              fixedHeight: root.iconBox
              tooltipText: modelData.title
              onPressed: function(button) {
                if (button === Qt.LeftButton)
                  Hyprland.dispatch("focuswindow address:" + modelData.address)
              }

              Rectangle {
                anchors.fill: parent
                radius: root.dp(Style.space(6))
                antialiasing: true
                color: appHover.hovered
                  ? (root.transparentBar
                    ? Util.alpha(root.adaptiveForeground, 0.18)
                    : (workspace.isSelected ? "#c9cace" : "#393a3f"))
                  : "transparent"

                Behavior on color { ColorAnimation { duration: 150; easing.type: Easing.OutCubic } }

                Image {
                  id: appIconImage
                  anchors.centerIn: parent
                  width: root.iconSize
                  height: root.iconSize
                  fillMode: Image.PreserveAspectFit
                  source: root.appIcon(app.modelData)
                  sourceSize.width: root.iconDecodeSize(root.iconSize)
                  sourceSize.height: root.iconDecodeSize(root.iconSize)
                  asynchronous: false
                  smooth: true
                  mipmap: true
                  // Drawn through the effect below, never directly.
                  visible: false
                  layer.enabled: true
                  layer.smooth: true
                  layer.textureSize: Qt.size(Math.round(width * root.dpr), Math.round(height * root.dpr))
                }

                MultiEffect {
                  anchors.fill: appIconImage
                  source: appIconImage
                  saturation: workspace.isSelected ? 0 : root.inactiveIconSaturation
                  opacity: workspace.isSelected ? 1 : root.inactiveIconOpacity

                  Behavior on saturation { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                  Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
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
