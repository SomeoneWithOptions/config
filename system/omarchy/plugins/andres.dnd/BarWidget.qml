import QtQuick
import qs.Ui

BarIconButton {
  id: root

  // Mirrors andres.idle, inverted in meaning: idle shows the icon when the
  // non-default state is on, and so does this one — normal is "notifications
  // allowed" (no icon), silenced is the state worth surfacing.
  readonly property var notificationService: bar?.shell?.serviceFor("andres.notifications")

  visible: notificationService ? notificationService.doNotDisturb : false
  text: "󰂛"
  tooltipText: "Notifications are silenced"
  interactive: true
  pressable: false
  useActiveColor: false
}
