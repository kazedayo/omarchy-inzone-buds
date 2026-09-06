function parseGetAll(raw) {
  var text = String(raw || "")
  var out = {
    ok: false,
    device: "",
    volume: 0,
    balance: 50,
    sidetone: 0,
    battery: null,
    batteryLeft: null,
    batteryRight: null,
    batteryCase: null,
    charging: false,
    ncMode: 0,
    micMuted: false
  }
  if (!text || /^Error:/i.test(text.trim())) return out

  function numAfter(label) {
    var m = text.match(new RegExp(label + "\\s+(-?\\d+)"))
    return m ? parseInt(m[1], 10) : null
  }

  function pctToken(token) {
    if (!token || token === "-") return null
    var n = parseInt(String(token).replace("%", ""), 10)
    return isFinite(n) ? n : null
  }

  var deviceM = text.match(/Device:\s*(.+)/)
  if (deviceM) out.device = deviceM[1].trim()

  var volume = numAfter("Volume:")
  if (volume !== null) out.volume = volume
  var balance = numAfter("Game/Chat Balance:")
  if (balance !== null) out.balance = balance
  var sidetone = numAfter("Sidetone:")
  if (sidetone !== null) out.sidetone = sidetone
  var ncMode = numAfter("Current Mode:")
  if (ncMode !== null) out.ncMode = ncMode

  var budsBat = text.match(/Battery L\/R\/Case:\s+(\S+)\s+\/\s+(\S+)\s+\/\s+(\S+)/)
  if (budsBat) {
    out.batteryLeft = pctToken(budsBat[1])
    out.batteryRight = pctToken(budsBat[2])
    out.batteryCase = pctToken(budsBat[3])
    var live = []
    if (out.batteryLeft !== null) live.push(out.batteryLeft)
    if (out.batteryRight !== null) live.push(out.batteryRight)
    if (live.length) out.battery = Math.min.apply(null, live)
  } else {
    var level = text.match(/Battery Level:\s+(\d+)%/)
    if (level) out.battery = parseInt(level[1], 10)
  }
  out.charging = /\(Charging\)/.test(text)
  out.micMuted = /Mic Muted:\s+On/.test(text)
  out.ok = volume !== null || ncMode !== null || !!out.device
  return out
}

function clamp(value, min, max) {
  var n = parseInt(value, 10)
  if (!isFinite(n)) n = min
  if (n < min) return min
  if (n > max) return max
  return n
}

function ncLabel(mode) {
  if (mode === 1) return "Noise Cancelling"
  if (mode === 2) return "Ambient Sound"
  return "Off"
}

function ncIcon(mode) {
  if (mode === 1) return "󰋋"
  if (mode === 2) return "󰥻"
  return "󰓃"
}

function formatPct(value) {
  return value === null || value === undefined ? "—" : (value + "%")
}

function errorStatus(raw) {
  var text = String(raw || "")
  if (/udev|permission/i.test(text)) return "Need udev access"
  if (/not found|No supported|Could not open/i.test(text)) return "Not connected"
  if (!text) return "Not connected"
  return "Not connected"
}
