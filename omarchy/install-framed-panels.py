#!/usr/bin/env python3
"""Generate user-owned Quattro panel clones attached to top desktop frame."""

import json
import os
import shutil
import tempfile
from pathlib import Path

PANEL_IDS = ("audio", "bluetooth", "clock", "monitor", "network", "power")


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
    x: root.screenW - root.frameInset - width
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
