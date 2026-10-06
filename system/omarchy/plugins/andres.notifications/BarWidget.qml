import QtQuick
import qs.Ui

BarIconButton {
  id: root

  // Keep the indicator in the service's plugin: scoped shell APIs only
  // expose a plugin's own service, just like andres.idle's bar widget.
  readonly property var notificationService: bar?.shell?.serviceFor("andres.notifications")

  visible: notificationService ? notificationService.doNotDisturb : false
  text: "󰂛"
  tooltipText: "Notifications are silenced"
  interactive: true
  pressable: false
  useActiveColor: false
}
