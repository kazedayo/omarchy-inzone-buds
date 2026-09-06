import QtQuick
import qs.Commons

// Right-side INZONE Bud. Ear hook is a ring behind the capsule — the
// housing covers the right half, so a C peeks out the inner side.
Item {
  id: root

  property real iconSize: Style.font.icon
  property color color: Color.foreground
  property color innerColor: Color.background

  width: iconSize
  height: iconSize
  implicitWidth: iconSize
  implicitHeight: iconSize

  readonly property real s: iconSize

  Item {
    id: bud
    width: root.s * 0.60
    height: root.s * 0.94
    rotation: 22
    anchors.centerIn: parent
    anchors.horizontalCenterOffset: root.s * 0.10

    // Silicone hook: full ring, mostly covered by the housing
    Rectangle {
      width: parent.width * 0.52
      height: width
      radius: width / 2
      color: "transparent"
      border.color: root.color
      border.width: Math.max(2, root.s * 0.14)
      x: -width * 0.38
      y: parent.height * 0.24
    }

    Rectangle {
      anchors.fill: parent
      radius: width * 0.50
      color: root.color
    }

    Rectangle {
      width: parent.width * 0.58
      height: parent.height * 0.54
      radius: width * 0.50
      color: root.innerColor
      anchors.horizontalCenter: parent.horizontalCenter
      y: parent.height * 0.34

      Rectangle {
        width: Math.min(parent.width * 0.48, parent.height * 0.34)
        height: width
        radius: width / 2
        color: root.color
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: parent.height * 0.10
      }
    }
  }
}
