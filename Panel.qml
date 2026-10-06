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
  // Hide the bar entry while the buds are away — the bar slot collapses to
  // zero width (same pattern as the built-in Tray widget). The poll timer
  // keeps running so the icon reappears on reconnect.
  visible: connected

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
  // Last non-event line from the monitor ("Listening..." / "Error: ...") — feeds
  // errorStatus() when the stream dies.
  property string lastMonitorLine: ""

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
    pendingSet = null
    battery = null
    batteryLeft = null
    batteryRight = null
    batteryCase = null
    if (opened) close()
  }

  // Long-running event stream. Its exit doubles as instant disconnect
  // detection; the 10 s battery poll remains the backstop. Coexists with
  // --get-all/--set (hidraw sharing verified).
  Process {
    id: monitorProc
    running: false
    command: ["env", "PYTHONUNBUFFERED=1", root.zoneoutBin, "--device", "buds", "--monitor"]
    stdout: SplitParser {
      onRead: function(line) {
        if (/^(Listening|Error:)/.test(line)) {
          root.lastMonitorLine = line
          return
        }
        var ev = Model.parseEvent(line)
        if (ev) root.handleEvent(ev.name, ev.value)
      }
    }
    stderr: StdioCollector { id: monitorStderr; waitForEnd: true }
    onExited: function(exitCode) {
      if (!root.ownsMonitor() || !root.connected) return
      var raw = root.lastMonitorLine + "\n" + monitorStderr.text
      root.markDisconnected(raw)
      root.broadcast("markDisconnected", raw)
    }
  }

  // A bar surface exists per monitor, so relay to every live instance of this
  // widget — otherwise a change made on one screen leaves the others stale.
  // Extra arguments are forwarded to the target method.
  function broadcast(method) {
    var args = Array.prototype.slice.call(arguments, 1)
    var items = bar && typeof bar.moduleWidgets === "function" ? bar.moduleWidgets(moduleName) : [root]
    for (var i = 0; i < items.length; i++) {
      if (items[i] && typeof items[i][method] === "function") items[i][method].apply(items[i], args)
    }
  }

  function applyLocal(name, value) {
    if (name === "nc_mode") ncMode = value
    else if (name === "volume") volume = value
    else if (name === "balance") balance = value
    else if (name === "sidetone") sidetone = value
  }

  // Event-stream counterpart of applyStatus: instant state for changes made
  // on the buds themselves or by other tools (sidetone has no event id).
  function applyEvent(name, value) {
    connected = true
    lastError = ""
    if (name === "mic_muted") micMuted = !!value
    else if (name === "nc_mode") ncMode = value
    else if (name === "volume" && !dragging(volumeSlider)) volume = value
    else if (name === "balance" && !dragging(balanceSlider)) balance = value
  }

  function handleEvent(name, value) {
    applyEvent(name, value)
    broadcast("applyEvent", name, value)
  }

  // One instance owns the event stream (moduleWidgets order), same as the
  // poll timer; events are broadcast to the sibling instances.
  function ownsMonitor() {
    var items = bar && typeof bar.moduleWidgets === "function" ? bar.moduleWidgets(moduleName) : [root]
    return items[0] === root
  }

  // PYTHONUNBUFFERED is load-bearing: piped python block-buffers stdout and
  // events never reach the parser.
  function startMonitor() {
    if (monitorProc.running) return
    lastMonitorLine = ""
    monitorProc.running = true
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
  onConnectedChanged: if (connected && ownsMonitor()) startMonitor()

  Process {
    id: getProc
    running: false
    command: [root.zoneoutBin, "--device", "buds", "--get-all"]
    stdout: StdioCollector { id: getStdout; waitForEnd: true }
    stderr: StdioCollector { id: getStderr; waitForEnd: true }
    onExited: function(exitCode) {
      if (root.pendingSet && !setProc.running) {
        var queued = root.pendingSet
        root.pendingSet = null
        root.runSet(queued.name, queued.value)
      }
      if (root.activeFetchGen !== root.fetchGen) return
      var raw = getStdout.text + "\n" + getStderr.text
      if (exitCode !== 0) {
        root.markDisconnected(raw)
        root.broadcast("markDisconnected", raw)
        return
      }
      var status = Model.parseGetAll(getStdout.text)
      if (status.ok) {
        root.applyStatus(status)
        root.broadcast("applyStatus", status)
      } else {
        root.markDisconnected(raw)
        root.broadcast("markDisconnected", raw)
      }
    }
  }

  Process {
    id: setProc
    running: false
    command: [root.zoneoutBin, "--device", "buds", "--set", "volume", "0"]
    stdout: StdioCollector { id: setStdout; waitForEnd: true }
    stderr: StdioCollector { id: setStderr; waitForEnd: true }
    onExited: function(exitCode) {
      var raw = setStdout.text + "\n" + setStderr.text
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
        return
      }
      root.broadcast("refresh")
    }
  }

  // Adaptive poll: fast reconnect probe while down, slow battery refresh
  // while up (the event stream carries state; battery has no events). One
  // instance polls and owns the monitor (moduleWidgets order); broadcast()
  // syncs the rest. refresh() no-ops while a fetch is already running.
  Timer {
    interval: root.connected ? 10000 : 3000
    repeat: true
    running: true
    onTriggered: {
      if (!root.ownsMonitor()) return
      if (root.connected) root.startMonitor()
      root.refresh()
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    tooltipText: root.deviceName
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
    // First-party panels hand off bar-strip clicks through bar.clickTargets,
    // but the third-party facade scopes that list to this plugin's own
    // button, so a click on any other toolbar icon only dismissed us. Cut
    // the bar window out of the input mask instead: clicks there fall
    // through to the bar surface, the clicked widget opens its own panel,
    // and the bar's popout coordinator closes this one — one-click panel
    // switching with the first-party fade choreography.
    // ponytail: clicks on empty bar background no longer dismiss (they land
    // on the bar's own surface, as with no panel open); restore parity if the
    // shell facade ever exposes other widgets' click targets to plugins.
    mask: Region {
      width: panel.screenW
      height: panel.screenH

      Region {
        intersection: Intersection.Subtract
        x: panel.barPos === "right" ? panel.screenW - panel.barW : 0
        y: panel.barPos === "bottom" ? panel.screenH - panel.barH : 0
        width: panel.barPos === "left" || panel.barPos === "right" ? panel.barW : panel.screenW
        height: panel.barPos === "top" || panel.barPos === "bottom" ? panel.barH : panel.screenH
      }
    }
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

  component InfoPair: Item {
    property string label: ""
    property string value: ""

    width: parent.width
    height: labelItem.implicitHeight

    Text {
      id: labelItem
      textFormat: Text.PlainText
      text: label
      color: root.bar.foreground
      opacity: 0.6
      font.family: root.bar.fontFamily
      font.pixelSize: Style.font.bodySmall
      anchors.left: parent.left
    }

    Text {
      textFormat: Text.PlainText
      text: value
      color: root.bar.foreground
      font.family: root.bar.fontFamily
      font.pixelSize: Style.font.bodySmall
      anchors.right: parent.right
    }
  }
}
