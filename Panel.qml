import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root
  moduleName: "io.github.kaz.omarchy-inzone-buds"
  ipcTarget: "io.github.kaz.omarchy-inzone-buds"

  property bool connected: false
  property string deviceName: "INZONE Buds"
  property string lastError: ""
  property int ncMode: 0
  property int volume: 0
  property int balance: 50
  property int sidetone: 0
  property var battery: null
  property var batteryLeft: null
  property var batteryRight: null
  property var batteryCase: null
  property bool charging: false
  property bool micMuted: false
  property int fetchGen: 0
  property int activeFetchGen: 0
  // ponytail: one pending HID write; queue-per-field if overlapping sliders lag
  property var pendingSet: null
  property string _getOut: ""
  property string _getErr: ""
  property string _setOut: ""
  property string _setErr: ""

  readonly property var ncModes: [
    { id: 0, label: "Off" },
    { id: 1, label: "ANC" },
    { id: 2, label: "Ambient" }
  ]
  readonly property string heroStatusText: {
    if (!connected) return lastError || "Not connected"
    if (micMuted) return "Mic muted"
    return Model.ncLabel(ncMode)
  }
  readonly property bool hasBattery: battery !== null || batteryLeft !== null || batteryRight !== null || batteryCase !== null
  readonly property color dim: Qt.darker(barForeground, 1.4)
  readonly property string zoneoutBin: (Quickshell.env("HOME") || "") + "/.local/bin/zoneout"

  function refresh() {
    if (getProc.running || setProc.running) return
    activeFetchGen = ++fetchGen
    _getOut = ""
    _getErr = ""
    getProc.running = true
  }

  function dragging(item) {
    return !!(item && item.dragging)
  }

  function applyStatus(status) {
    connected = true
    lastError = ""
    if (status.device) deviceName = status.device
    ncMode = status.ncMode
    if (!dragging(volumeSlider)) volume = status.volume
    if (!dragging(balanceSlider)) balance = status.balance
    if (!dragging(sidetoneSlider)) sidetone = status.sidetone
    battery = status.battery
    batteryLeft = status.batteryLeft
    batteryRight = status.batteryRight
    batteryCase = status.batteryCase
    charging = status.charging
    micMuted = status.micMuted
  }

  function markDisconnected(raw) {
    connected = false
    lastError = Model.errorStatus(raw)
  }

  function applyLocal(name, value) {
    if (name === "nc_mode") ncMode = value
    else if (name === "volume") volume = value
    else if (name === "balance") balance = value
    else if (name === "sidetone") sidetone = value
  }

  function setVar(name, value) {
    var next = value
    if (name === "nc_mode") next = Model.clamp(value, 0, 2)
    else if (name === "volume") next = Model.clamp(value, 0, 30)
    else if (name === "balance") next = Model.clamp(value, 0, 100)
    else if (name === "sidetone") next = Model.clamp(value, 0, 10)
    else return

    fetchGen++
    applyLocal(name, next)
    if (getProc.running || setProc.running) {
      pendingSet = { name: name, value: next }
      return
    }
    runSet(name, next)
  }

  function runSet(name, value) {
    _setOut = ""
    _setErr = ""
    setProc.command = [root.zoneoutBin, "--device", "buds", "--set", name, String(value)]
    setProc.running = true
  }

  function cycleNc() {
    if (!connected) {
      refresh()
      return
    }
    setVar("nc_mode", (ncMode + 1) % 3)
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  Component.onCompleted: refresh()
  onOpenedChanged: if (opened) refresh()

  Process {
    id: getProc
    running: false
    command: [root.zoneoutBin, "--device", "buds", "--get-all"]
    stdout: StdioCollector { id: getStdout; waitForEnd: true; onStreamFinished: root._getOut = text }
    stderr: StdioCollector { id: getStderr; waitForEnd: true; onStreamFinished: root._getErr = text }
    onExited: function(exitCode) {
      if (root.activeFetchGen !== root.fetchGen) return
      var raw = String(getStdout.text || root._getOut || "") + "\n" + String(getStderr.text || root._getErr || "")
      if (exitCode !== 0) {
        root.markDisconnected(raw)
        return
      }
      var status = Model.parseGetAll(root._getOut || getStdout.text)
      if (status.ok) root.applyStatus(status)
      else root.markDisconnected(raw)
    }
  }

  Process {
    id: setProc
    running: false
    command: [root.zoneoutBin, "--device", "buds", "--set", "volume", "0"]
    stdout: StdioCollector { id: setStdout; waitForEnd: true; onStreamFinished: root._setOut = text }
    stderr: StdioCollector { id: setStderr; waitForEnd: true; onStreamFinished: root._setErr = text }
    onExited: function(exitCode) {
      var raw = String(setStdout.text || root._setOut || "") + "\n" + String(setStderr.text || root._setErr || "")
      if (exitCode !== 0) {
        root.pendingSet = null
        root.markDisconnected(raw)
        root.refresh()
        return
      }
      root.lastError = ""
      if (root.pendingSet) {
        var pending = root.pendingSet
        root.pendingSet = null
        root.runSet(pending.name, pending.value)
      }
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    opacity: root.connected ? 1 : 0.45
    tooltipText: root.connected ? root.deviceName : "INZONE Buds"
    iconComponent: Component {
      Item {
        InzoneIcon {
          anchors.centerIn: parent
          iconSize: parent.width
          color: root.barForeground
          innerColor: root.bar ? root.bar.background : Color.background
        }
      }
    }
    onPressed: function(b) {
      if (b === Qt.RightButton) root.cycleNc()
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(380))
    contentHeight: panel.fittedContentHeight(column.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function(dx, dy) {
        if (!root.connected || dx === 0) return
        root.setVar("nc_mode", (root.ncMode + dx + 3) % 3)
      }
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Column {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Style.space(14)

        Item {
          width: parent.width
          implicitHeight: Math.max(heroIcon.implicitHeight, heroLabels.implicitHeight, heroPercent.implicitHeight)

          InzoneIcon {
            id: heroIcon
            iconSize: Style.font.display
            color: root.bar.foreground
            innerColor: root.bar.background
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            opacity: root.connected ? 1 : 0.5
          }

          Column {
            id: heroLabels
            anchors.left: heroIcon.right
            anchors.leftMargin: Style.space(14)
            anchors.right: heroPercent.left
            anchors.rightMargin: Style.space(10)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(2)

            Text {
              text: root.deviceName
              color: root.bar.foreground
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.title
              font.bold: true
              elide: Text.ElideRight
              width: parent.width
            }

            Text {
              textFormat: Text.PlainText
              text: root.heroStatusText.toUpperCase()
              color: root.dim
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
              font.letterSpacing: 1.2
              elide: Text.ElideRight
              width: parent.width
            }
          }

          Text {
            id: heroPercent
            textFormat: Text.PlainText
            text: Model.formatPct(root.battery)
            color: root.bar.foreground
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.displayLarge
            font.bold: true
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
          }
        }

        PanelSeparator { foreground: root.bar.foreground }

        Column {
          width: parent.width
          spacing: Style.space(10)
          opacity: root.connected ? 1 : 0.45

          PanelSectionHeader {
            text: "NOISE CONTROL"
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
          }

          Row {
            id: ncRow
            width: parent.width
            spacing: Style.space(6)
            readonly property real cellWidth: (width - spacing * (root.ncModes.length - 1)) / root.ncModes.length

            Repeater {
              model: root.ncModes
              Button {
                required property var modelData
                width: ncRow.cellWidth
                iconText: Model.ncIcon(modelData.id)
                iconSize: Style.font.title
                text: modelData.label
                fontSize: Style.font.bodySmall
                foreground: root.bar.foreground
                fontFamily: root.bar.fontFamily
                horizontalPadding: Style.spacing.controlPaddingX
                verticalPadding: Style.spacing.controlPaddingY + Style.space(2)
                bordered: true
                active: root.ncMode === modelData.id
                enabled: root.connected
                onClicked: root.setVar("nc_mode", modelData.id)
              }
            }
          }
        }

        PanelSeparator { foreground: root.bar.foreground }

        Column {
          width: parent.width
          spacing: Style.space(6)
          opacity: root.connected ? 1 : 0.45

          Item {
            width: parent.width
            implicitHeight: Math.max(volumeHeader.implicitHeight, volumeValue.implicitHeight)

            PanelSectionHeader {
              id: volumeHeader
              text: "VOLUME"
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
            }

            Text {
              id: volumeValue
              textFormat: Text.PlainText
              text: (volumeSlider.dragging ? Math.round(volumeSlider.liveValue) : root.volume) + "/30"
              color: root.dim
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
              anchors.right: parent.right
              anchors.rightMargin: Style.space(6)
              anchors.verticalCenter: parent.verticalCenter
            }
          }

          CursorSurface {
            width: parent.width
            height: volumeSlider.implicitHeight + Style.spacing.controlGap
            foreground: root.bar.foreground
            outline: true
            PanelSlider {
              id: volumeSlider
              bar: root.bar
              anchors.fill: parent
              anchors.leftMargin: Style.space(6)
              anchors.rightMargin: Style.space(6)
              minimum: 0
              maximum: 30
              step: 1
              integer: true
              value: root.volume
              enabled: root.connected
              onReleased: function(v) { root.setVar("volume", v) }
            }
          }
        }

        Column {
          width: parent.width
          spacing: Style.space(6)
          opacity: root.connected ? 1 : 0.45

          Item {
            width: parent.width
            implicitHeight: Math.max(balanceHeader.implicitHeight, balanceValue.implicitHeight)

            PanelSectionHeader {
              id: balanceHeader
              text: "GAME / CHAT"
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
            }

            Text {
              id: balanceValue
              textFormat: Text.PlainText
              text: String(balanceSlider.dragging ? Math.round(balanceSlider.liveValue) : root.balance)
              color: root.dim
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
              anchors.right: parent.right
              anchors.rightMargin: Style.space(6)
              anchors.verticalCenter: parent.verticalCenter
            }
          }

          CursorSurface {
            width: parent.width
            height: balanceSlider.implicitHeight + Style.spacing.controlGap
            foreground: root.bar.foreground
            outline: true
            PanelSlider {
              id: balanceSlider
              bar: root.bar
              anchors.fill: parent
              anchors.leftMargin: Style.space(6)
              anchors.rightMargin: Style.space(6)
              minimum: 0
              maximum: 100
              step: 1
              integer: true
              value: root.balance
              enabled: root.connected
              onReleased: function(v) { root.setVar("balance", v) }
            }
          }
        }

        Column {
          width: parent.width
          spacing: Style.space(6)
          opacity: root.connected ? 1 : 0.45

          Item {
            width: parent.width
            implicitHeight: Math.max(sidetoneHeader.implicitHeight, sidetoneValue.implicitHeight)

            PanelSectionHeader {
              id: sidetoneHeader
              text: "SIDETONE"
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
            }

            Text {
              id: sidetoneValue
              textFormat: Text.PlainText
              text: (sidetoneSlider.dragging ? Math.round(sidetoneSlider.liveValue) : root.sidetone) + "/10"
              color: root.dim
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
              anchors.right: parent.right
              anchors.rightMargin: Style.space(6)
              anchors.verticalCenter: parent.verticalCenter
            }
          }

          CursorSurface {
            width: parent.width
            height: sidetoneSlider.implicitHeight + Style.spacing.controlGap
            foreground: root.bar.foreground
            outline: true
            PanelSlider {
              id: sidetoneSlider
              bar: root.bar
              anchors.fill: parent
              anchors.leftMargin: Style.space(6)
              anchors.rightMargin: Style.space(6)
              minimum: 0
              maximum: 10
              step: 1
              integer: true
              value: root.sidetone
              enabled: root.connected
              onReleased: function(v) { root.setVar("sidetone", v) }
            }
          }
        }

        PanelSeparator {
          visible: root.hasBattery
          foreground: root.bar.foreground
        }

        Column {
          visible: root.hasBattery
          width: parent.width
          spacing: Style.space(10)

          PanelSectionHeader {
            text: "BATTERY"
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
          }

          Row {
            width: parent.width
            spacing: Style.space(20)

            Column {
              width: (parent.width - parent.spacing) / 2
              spacing: Style.spacing.labelGap
              InfoPair { label: "Left"; value: Model.formatPct(root.batteryLeft) }
              InfoPair { label: "Right"; value: Model.formatPct(root.batteryRight) }
            }

            Column {
              width: (parent.width - parent.spacing) / 2
              spacing: Style.spacing.labelGap
              InfoPair { label: "Case"; value: Model.formatPct(root.batteryCase) }
              InfoPair { label: "State"; value: root.charging ? "Charging" : (root.connected ? "In use" : "—") }
            }
          }
        }
      }
    }
  }

  component InfoPair: Row {
    property string label: ""
    property string value: ""

    width: parent.width
    spacing: Style.space(8)

    Text {
      textFormat: Text.PlainText
      text: label
      color: root.bar.foreground
      opacity: 0.6
      font.family: root.bar.fontFamily
      font.pixelSize: Style.font.bodySmall
    }
    Item {
      width: Math.max(0, parent.width - parent.children[0].implicitWidth - parent.children[2].implicitWidth - parent.spacing * 2)
      height: 1
    }
    Text {
      textFormat: Text.PlainText
      text: value
      color: root.bar.foreground
      font.family: root.bar.fontFamily
      font.pixelSize: Style.font.bodySmall
    }
  }
}
