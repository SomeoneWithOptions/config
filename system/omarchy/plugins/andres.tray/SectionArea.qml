import QtQuick

// Separate type: Qt's linter cannot resolve a shared inline component from
// both orientation Components in Tray.qml. The runtime contract is unchanged.
Item {
  id: area
  required property var owner
  implicitWidth: childrenRect.width
  implicitHeight: childrenRect.height
  Component.onCompleted: owner.sectionHost = area
  Component.onDestruction: if (owner && owner.sectionHost === area) owner.sectionHost = null
}
