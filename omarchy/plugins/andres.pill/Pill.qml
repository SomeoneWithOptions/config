import QtQuick
import qs.Commons
import qs.Ui

// Pre-Quattro bar grouping: one rounded pill behind every widget that follows
// this one, up to the next pill (or the end of the section). Placed first in
// each run of widgets, so it paints under its group.
BarWidget {
  id: root
  moduleName: "andres.pill"

  readonly property int gap: Number(setting("gap", 8))          // between pills — 8 matches Style.spacing
  readonly property int pad: Number(setting("padding", 10))       // group to pill edge — breathable
  readonly property int thickness: Number(setting("height", 30))
  readonly property color tint: root.bar ? root.bar.barForeground : Color.bar.text
  readonly property color fill: Util.alpha(tint, 0.14)
  readonly property color stroke: root.bar && root.bar.transparent
    ? Util.alpha(tint, 0.24) : Color.popups.border

  // The bar wraps each widget in a ModuleSlot inside one Row/Column per
  // section; the group is every sibling slot after ours.
  readonly property Item slot: {
    var node = parent
    while (node) {
      if ("region" in node && "moduleName" in node) return node
      node = node.parent
    }
    return null
  }
  readonly property Item lane: slot ? slot.parent : null
  // Any widget resizing changes the lane's own size, which is the cue to
  // re-measure. ponytail: two siblings swapping equal sizes in one frame would
  // go unmeasured; nothing in the bar does that.
  readonly property real laneExtent: !lane ? 0 : (vertical ? lane.height : lane.width)
  property real extent: 0

  function measure() {
    var kids = lane ? lane.children : []
    var total = 0
    var inGroup = false
    for (var i = 0; i < kids.length; i++) {
      if (kids[i] === slot) { inGroup = true; continue }
      if (!inGroup) continue
      // A spacer is blank room between groups, never part of one.
      if (kids[i].moduleName === root.moduleName || kids[i].moduleName === "omarchy.spacer") break
      total += vertical ? kids[i].height : kids[i].width
    }
    extent = total
  }

  onLaneExtentChanged: Qt.callLater(measure)
  Component.onCompleted: Qt.callLater(measure)

  implicitWidth: vertical ? barSize : (extent > 0 ? gap + pad * 2 : 0)
  implicitHeight: vertical ? (extent > 0 ? gap + pad * 2 : 0) : barSize

  Behavior on extent {
    NumberAnimation { duration: 260; easing.type: Easing.OutCubic }
  }
  Behavior on implicitWidth {
    NumberAnimation { duration: 260; easing.type: Easing.OutExpo }
  }
  Behavior on implicitHeight {
    NumberAnimation { duration: 260; easing.type: Easing.OutExpo }
  }

  Rectangle {
    visible: root.extent > 0
    x: root.vertical ? Math.round((root.width - width) / 2) : root.gap + root.pad
    y: root.vertical ? root.gap + root.pad : Math.round((root.height - height) / 2)
    width: root.vertical ? root.thickness : root.extent + root.pad * 2
    height: root.vertical ? root.extent + root.pad * 2 : root.thickness
    radius: Math.min(width, height) / 2
    color: root.fill
    border.width: 1
    border.color: root.stroke
    antialiasing: true
    smooth: true

    Behavior on width { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
    Behavior on height { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
    Behavior on color { ColorAnimation { duration: 180; easing.type: Easing.OutCubic } }
    Behavior on border.color { ColorAnimation { duration: 180; easing.type: Easing.OutCubic } }
  }
}
