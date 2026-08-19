import QtQuick
import qs.Ui

BarIconButton {
  id: root

  readonly property var idleService: bar?.shell?.serviceFor("andres.idle")

  visible: idleService ? idleService.stayAwake : false
  text: "󰅶"
  tooltipText: "Stay awake is active"
  interactive: true
  pressable: false
  useActiveColor: false
}
