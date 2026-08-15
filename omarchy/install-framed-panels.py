#!/usr/bin/env python3
"""Generate user-owned Quattro panel clones attached to top desktop frame."""

import json
import os
import shutil
import tempfile
from pathlib import Path

PANEL_IDS = ("audio", "bluetooth", "clock", "monitor", "network", "power", "tailscale")


def replace_once(text, old, new, source):
    if text.count(old) != 1:
        raise RuntimeError(f"{source}: expected one {old!r}, found {text.count(old)}")
    return text.replace(old, new)


def same_tree(left, right):
    if not right.is_dir():
        return False
    left_files = {p.relative_to(left): p.read_bytes() for p in left.rglob("*") if p.is_file()}
    right_files = {p.relative_to(right): p.read_bytes() for p in right.rglob("*") if p.is_file()}
    return left_files == right_files


def patch_power_model(text, source):
    """Add the pre-Quattro Material Symbols battery ladder next to the Nerd Font one."""
    text = replace_once(
        text,
        "function modeLabel(device, onBattery, states) {",
        """// Bar glyph: Material Symbols ligature names (pre-Quattro battery_android set).
// Kept separate from batteryIcon() because the panel hero still paints in the
// bar's Nerd Font.
function batteryGlyph(device, onBattery, states) {
  var d = device || {}
  if (!d.isPresent) return ""

  var percent = Math.round((d.percentage || 0) * 100)
  if (!onBattery && !chargeThresholdActive(d, onBattery, states)) return "battery_android_frame_bolt"
  if (percent >= 95) return "battery_android_full"
  if (percent >= 80) return "battery_android_6"
  if (percent >= 65) return "battery_android_5"
  if (percent >= 50) return "battery_android_4"
  if (percent >= 35) return "battery_android_3"
  if (percent >= 20) return "battery_android_2"
  if (percent >= 10) return "battery_android_1"
  return "battery_android_0"
}

function modeLabel(device, onBattery, states) {""",
        source,
    )
    return replace_once(
        text,
        "    batteryIcon: batteryIcon,",
        "    batteryIcon: batteryIcon,\n    batteryGlyph: batteryGlyph,",
        source,
    )


def patch_power_panel(text, source):
    """Bar widget paints the Material Symbols glyph plus the percentage, as before Quattro."""
    text = replace_once(
        text,
        """  // With the percentage shown the button paints a text block wider than an
  // icon, so the open-panel mark takes the painted width instead of the
  // icon-sized fraction of the slot the fallback assumes.
  readonly property real openPanelIndicatorWidth: showPercentage && !button.vertical ? button.glyphPaintedWidth : 0""",
        """  // The button paints a glyph + label block wider than an icon, so the
  // open-panel mark takes the painted width instead of the icon-sized
  // fraction of the slot the fallback assumes.
  readonly property real openPanelIndicatorWidth: button.vertical ? 0 : content.implicitWidth
  readonly property bool batteryAlert: discharging && batteryFraction <= 0.15
  // Pre-Quattro bar tint: yellow saver, theme foreground balanced, green performance.
  readonly property color profileTint: {
    if (root.activeProfile === "power-saver") return "#e0af68"
    if (root.activeProfile === "performance") return "#9ece6a"
    return button.foreground
  }""",
        source,
    )
    text = replace_once(
        text,
        """  Process {
    id: batteryProc""",
        """  // activeProfile is only refreshed while the panel is open, but the bar tint
  // needs it always. powerprofilesd announces switches on the system bus, so
  // one long-lived monitor replaces polling powerprofilesctl on a timer.
  Process {
    running: true
    command: ["busctl", "get-property", "net.hadess.PowerProfiles", "/net/hadess/PowerProfiles", "net.hadess.PowerProfiles", "ActiveProfile"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var initial = text.match(/"([a-z-]+)"/)
        if (initial) root.activeProfile = initial[1]
      }
    }
  }

  Process {
    running: true
    command: ["gdbus", "monitor", "--system", "--dest", "net.hadess.PowerProfiles"]
    stdout: SplitParser {
      onRead: function(line) {
        var changed = String(line).match(/'ActiveProfile': <'([a-z-]+)'>/)
        if (changed) root.activeProfile = changed[1]
      }
    }
  }

  Process {
    id: batteryProc""",
        source,
    )
    text = replace_once(
        text,
        "  function modeLabel() {",
        """  function batteryGlyph() {
    return Model.batteryGlyph(UPower.displayDevice, root.discharging, upowerStates())
  }

  function modeLabel() {""",
        source,
    )
    return replace_once(
        text,
        """  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.showPercentage && !vertical
      ? Math.round(root.batteryFraction * 100) + "% " + root.batteryIcon()
      : root.batteryIcon()
    slotSize: Style.bar.iconSlot * (root.showPercentage && !vertical ? 2 : 1)
    tooltipText: ""
    onPressed: function(b) {
      if (!root.batteryPresent) return
      if (b === Qt.RightButton) root.togglePercentage()
      else root.toggle()
    }
  }""",
        """  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    labelVisible: false
    hasVisualContent: root.batteryPresent
    fixedWidth: vertical ? -1 : content.implicitWidth + Style.spaceReal(9) * 2
    fixedHeight: vertical ? Style.bar.iconSlot : -1
    tooltipText: ""
    onPressed: function(b) {
      if (!root.batteryPresent) return
      if (b === Qt.RightButton) root.togglePercentage()
      else root.toggle()
    }

    Row {
      id: content
      anchors.centerIn: parent
      spacing: Style.space(3)

      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: root.batteryGlyph()
        color: root.batteryAlert ? Color.urgent : root.profileTint
        // Material Symbols paint smaller than the Nerd Font glyphs the other
        // widgets use, so the icon runs a few px larger to match them.
        font.family: "Material Symbols Rounded"
        font.pixelSize: Style.bar.iconFont + 4
        font.variableAxes: ({ "FILL": 1 })
        // The Material Symbols ink box sits ~0.07em above the center of its
        // line box, so centering the Text leaves the battery riding high over
        // the percentage. Push it back down.
        anchors.verticalCenterOffset: Math.round(font.pixelSize * 0.07)
        renderType: Text.NativeRendering

        Behavior on color { ColorAnimation { duration: 160 } }
      }

      Text {
        visible: root.showPercentage && !button.vertical
        anchors.verticalCenter: parent.verticalCenter
        text: Math.round(root.batteryFraction * 100) + "%"
        color: root.batteryAlert ? Color.urgent : root.profileTint
        font.family: button.fontFamily
        font.pixelSize: Style.font.body
        renderType: Text.NativeRendering

        Behavior on color { ColorAnimation { duration: 160 } }
      }
    }
  }""",
        source,
    )


def patch_monitor_panel(text, source):
    """Add a gamma slider beneath brightness, wired to hyprsunset.

    Backlight brightness bottoms out well above what a dark room wants; gamma
    (the CTM hyprsunset drives) takes it the rest of the way. The row behaves
    exactly like the brightness row, so it joins the same j/k cursor model.
    """
    text = replace_once(
        text,
        "  property bool brightnessAvailable: false\n",
        "  property bool brightnessAvailable: false\n"
        "  // Identity until hyprsunset answers; a stopped daemon means no CTM.\n"
        "  property int gammaPercent: 100\n",
        source,
    )
    text = replace_once(
        text,
        '    if (brightnessAvailable) list.push("brightness")\n',
        '    if (brightnessAvailable) list.push("brightness")\n'
        '    list.push("gamma")\n',
        source,
    )
    text = replace_once(
        text,
        '    if (section === "brightness") return 0  // only the slider sentinel at -1',
        '    if (section === "brightness" || section === "gamma") return 0  // only the slider sentinel at -1',
        source,
    )
    text = replace_once(
        text,
        '    return section === "brightness" || section === "textsize" || section === "scale"',
        '    return section === "brightness" || section === "gamma" || section === "textsize" || section === "scale"',
        source,
    )
    text = replace_once(
        text,
        '    if (section === "brightness" || section === "textsize") return -1',
        '    if (section === "brightness" || section === "gamma" || section === "textsize") return -1',
        source,
    )
    text = replace_once(
        text,
        '      if (focusSection === "brightness" || focusSection === "textsize") selectedIndex = -1',
        '      if (focusSection === "brightness" || focusSection === "gamma" || focusSection === "textsize") selectedIndex = -1',
        source,
    )
    text = replace_once(
        text,
        '          if (root.focusSection === "brightness") root.adjustBrightness(dx * 5)',
        '          if (root.focusSection === "brightness") root.adjustBrightness(dx * 5)\n'
        '          else if (root.focusSection === "gamma") root.adjustGamma(dx * 5)',
        source,
    )
    text = replace_once(
        text,
        "  function refresh() {\n    if (!stateProc.running) stateProc.running = true\n  }",
        "  function refresh() {\n"
        "    if (!stateProc.running) stateProc.running = true\n"
        "    if (!gammaProc.running) gammaProc.running = true\n"
        "  }",
        source,
    )
    text = replace_once(
        text,
        "  function previewBrightness(value) {",
        """  function clampGamma(value) {
    // Floor at 10%: below that the screen is unreadable and the slider is the
    // only way back up.
    return Math.max(10, Math.min(100, Math.round(value)))
  }

  function setGamma(value) {
    root.gammaPercent = root.clampGamma(value)
    // Drags are debounced to ~180ms and every release writes again, so a
    // dropped in-flight write costs nothing.
    if (setGammaProc.running) return
    setGammaProc.command = ["hyprsunset-gamma-display", "--no-osd", String(root.gammaPercent)]
    setGammaProc.running = true
  }

  function previewGamma(value) {
    root.gammaPercent = root.clampGamma(value)
    gammaDebounce.restart()
  }

  function adjustGamma(delta) {
    if (focusSection !== "gamma") return
    setGamma(root.gammaPercent + delta)
  }

  function previewBrightness(value) {""",
        source,
    )
    text = replace_once(
        text,
        "  Timer {\n    id: brightnessDebounce",
        """  Process {
    id: gammaProc
    command: ["hyprctl", "hyprsunset", "gamma"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var parsed = parseInt(String(text || "").trim(), 10)
        // Daemon not running yet -> nothing is dimming the screen.
        root.gammaPercent = isNaN(parsed) ? 100 : root.clampGamma(parsed)
      }
    }
  }

  Timer {
    id: gammaDebounce
    interval: 180
    repeat: false
    onTriggered: root.setGamma(root.gammaPercent)
  }

  Process {
    id: setGammaProc
    stdout: StdioCollector { waitForEnd: true }
  }

  Timer {
    id: brightnessDebounce""",
        source,
    )
    return replace_once(
        text,
        "          // ---------- Text size ----------",
        """          // ---------- Gamma ----------
          PanelSeparator {
            foreground: root.bar.foreground
          }

          Column {
            width: parent.width
            spacing: Style.space(6)

            Item {
              width: parent.width
              implicitHeight: Math.max(gammaHeader.implicitHeight, gammaValueText.implicitHeight)

              PanelSectionHeader {
                id: gammaHeader
                text: "GAMMA"
                foreground: root.bar.foreground
                fontFamily: root.bar.fontFamily
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
              }

              Text {
                id: gammaValueText
                text: Math.round(gammaSlider.dragging ? gammaSlider.liveValue : root.gammaPercent) + "%"
                color: Qt.darker(root.bar.foreground, 1.4)
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                anchors.right: parent.right
                anchors.rightMargin: Style.space(6)
                anchors.verticalCenter: parent.verticalCenter
              }
            }

            CursorSurface {
              id: gammaRow
              width: parent.width
              height: gammaSlider.implicitHeight + Style.spacing.controlGap
              hasCursor: root.cursorActive && root.focusSection === "gamma" && root.selectedIndex === -1
              onHasCursorChanged: if (hasCursor) root.ensureCursorVisible(gammaRow)
              foreground: root.bar.foreground
              outline: true

              PanelSlider {
                id: gammaSlider
                bar: root.bar
                anchors.fill: parent
                anchors.leftMargin: Style.space(6)
                anchors.rightMargin: Style.space(6)
                minimum: 10
                maximum: 100
                step: 1
                value: root.gammaPercent
                integer: true
                onMoved: function(v) { root.previewGamma(v) }
                onReleased: function(v) {
                  gammaDebounce.stop()
                  root.setGamma(v)
                }
              }

              HoverHandler {
                onHoveredChanged: if (hovered && !root.reflowingText) {
                  root.cursorActive = true
                  root.focusSection = "gamma"
                  root.selectedIndex = -1
                }
              }
            }
          }

          // ---------- Text size ----------""",
        source,
    )


def install():
    shell_root = Path(os.environ.get("OMARCHY_SHELL_ROOT", "/usr/share/omarchy/shell"))
    config_root = Path(os.environ.get("OMARCHY_CONFIG_ROOT", Path.home() / ".config/omarchy"))
    frame_join = Path(__file__).parent / "plugins/andres.menu/FrameJoin.qml"

    keyboard_path = shell_root / "Ui/KeyboardPanel.qml"
    keyboard = keyboard_path.read_text()
    keyboard = replace_once(
        keyboard, "import qs.Commons", "import qs.Commons\nimport qs.Ui", keyboard_path
    )
    keyboard = replace_once(
        keyboard,
        "  property int gap: Style.gapsOut  // distance between bar edge and panel",
        """  property int gap: -1  // overlap top bar so panel grows directly from frame
  property int frameInset: 10  // matches Hyprland gaps_out
  readonly property bool attachedRight: barPos === "top"
    && Math.abs(cardOrigin.x + contentWidth - (screenW - frameInset)) < 1
  readonly property bool reduceMotion: Quickshell.env("DESKTOP_FRAME_REDUCED_MOTION") === "1"
  property real reveal: open || popoutSwitching ? 1 : 0

  Behavior on reveal {
    NumberAnimation {
      duration: root.reduceMotion ? 0 : (root.open ? 240 : 180)
      easing.type: Easing.OutExpo
    }
  }""",
        keyboard_path,
    )
    keyboard = replace_once(
        keyboard,
        "  visible: open || card.opacity > 0 || popoutSwitching",
        "  visible: open || reveal > 0 || popoutSwitching",
        keyboard_path,
    )
    keyboard = replace_once(
        keyboard,
        """  readonly property real availableCardHeight: screenH > 0
    ? Math.max(120, screenH - ((barPos === "top" || barPos === "bottom") ? barH + gap + margin : margin * 2))
    : 0""",
        """  readonly property real availableCardHeight: screenH > 0
    ? Math.max(120, screenH - ((barPos === "top" || barPos === "bottom")
      ? barH + gap + (barPos === "top" ? frameInset + Style.cornerRadius : margin)
      : margin * 2))
    : 0""",
        keyboard_path,
    )
    keyboard = replace_once(
        keyboard,
        "    x = Math.max(margin, Math.min(x, screenW - contentWidth - margin))",
        """    var rightMargin = barPos === "top" ? frameInset : margin
    x = Math.max(margin, Math.min(x, screenW - contentWidth - rightMargin))""",
        keyboard_path,
    )
    keyboard = replace_once(
        keyboard,
        "  // --- card ----------------------------------------------------------------\n\n  BorderSurface {",
        """  // --- card ----------------------------------------------------------------

  Item {
    id: revealClip
    x: 0
    y: root.cardOrigin.y
    width: root.screenW
    height: Math.round((root.contentHeight + Style.cornerRadius) * root.reveal)
    clip: true
  }

  FrameJoin {
    parent: revealClip
    visible: root.barPos === "top"
    x: card.x - width
    y: 0
    opacity: card.opacity
    cornerRadius: Style.cornerRadius
    frameColor: Color.popups.background
  }

  FrameJoin {
    id: topRightFrameJoin
    parent: revealClip
    visible: root.barPos === "top" && !root.attachedRight
    x: card.x + card.width
    y: 0
    opacity: card.opacity
    cornerRadius: Style.cornerRadius
    frameColor: Color.popups.background
    transform: Scale { origin.x: topRightFrameJoin.width / 2; xScale: -1 }
  }

  // A panel pinned to the right runs into the screen edge instead: the strip
  // bridges the gaps_out inset, and the fillet below curves into the edge.
  Rectangle {
    parent: revealClip
    visible: root.attachedRight
    x: card.x + card.width
    y: 0
    width: root.frameInset
    height: card.height
    color: Color.popups.background
    opacity: card.opacity
  }

  FrameJoin {
    parent: revealClip
    visible: root.attachedRight
    x: root.screenW - width
    y: card.height
    opacity: card.opacity
    cornerRadius: Style.cornerRadius
    frameColor: Color.popups.background
  }

  BorderSurface {
    parent: revealClip""",
        keyboard_path,
    )
    keyboard = replace_once(
        keyboard,
        """  BorderSurface {
    parent: revealClip
    id: card
    x: root.cardOrigin.x
    y: root.cardOrigin.y""",
        """  BorderSurface {
    parent: revealClip
    id: card
    x: root.cardOrigin.x
    y: 0""",
        keyboard_path,
    )
    keyboard = replace_once(
        keyboard,
        """    borderSpec: root.borderSpec
    padding: root.padding
    radius: Style.cornerRadius
    opacity: root.open || root.popoutSwitching ? 1.0 : 0

    Behavior on opacity {
      enabled: !root.popoutSwitching && !root.popoutSwitchClosing
      NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
    }
""",
        """    borderSpec: root.barPos === "top" ? Border.none() : root.borderSpec
    padding: root.padding
    radius: Style.cornerRadius
    topLeftRadius: root.barPos === "top" ? 0 : Style.cornerRadius
    topRightRadius: root.barPos === "top" ? 0 : Style.cornerRadius
    bottomRightRadius: root.attachedRight ? 0 : Style.cornerRadius
    opacity: 1
""",
        keyboard_path,
    )

    plugins_dir = config_root / "plugins"
    plugins_dir.mkdir(parents=True, exist_ok=True)
    for panel_id in PANEL_IDS:
        source = shell_root / "plugins/panels" / panel_id
        target = plugins_dir / f"andres.{panel_id}"
        # Stage outside watched plugin tree; copying files there would trigger a
        # reload for every partial file instead of one finished directory swap.
        with tempfile.TemporaryDirectory(dir=config_root, prefix=f".panel-{panel_id}.") as tmp:
            staged = Path(tmp) / target.name
            shutil.copytree(source, staged)

            panel_path = staged / "Panel.qml"
            panel = replace_once(
                panel_path.read_text(), "  KeyboardPanel {", "  FramePanel {", panel_path
            )
            if panel_id == "monitor":
                panel = patch_monitor_panel(panel, panel_path)
            if panel_id == "power":
                panel = patch_power_panel(panel, panel_path)
                model_path = staged / "Model.js"
                model_path.write_text(patch_power_model(model_path.read_text(), model_path))
            panel_path.write_text(panel)
            (staged / "FramePanel.qml").write_text(keyboard)
            shutil.copy2(frame_join, staged / "FrameJoin.qml")

            manifest_path = staged / "manifest.json"
            manifest = json.loads(manifest_path.read_text())
            source_id = f"omarchy.{panel_id}"
            manifest["id"] = f"andres.{panel_id}"
            manifest["name"] = f"Framed {manifest['name']}"
            manifest.setdefault("barWidget", {})["displayName"] = manifest["name"]
            manifest["omarchy"] = {"clonedFrom": source_id}
            manifest_path.write_text(json.dumps(manifest, indent=2) + "\n")

            if same_tree(staged, target):
                continue
            if target.exists():
                shutil.rmtree(target)
            staged.rename(target)
            print(target)


if __name__ == "__main__":
    install()
