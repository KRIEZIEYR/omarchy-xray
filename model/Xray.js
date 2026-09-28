.pragma library

/*
 * Pure logic for the omarchy-xray widget: shaping `omarchy-xray status`
 * output for the panel, xray metrics -> traffic speeds, and labels.
 *
 * Plain ES5 so tests/run.js can load this file under Node without a QML
 * engine. The QML side only supplies process plumbing.
 */

function elide(s, n) {
  s = String(s || "")
  return s.length > n ? s.substring(0, n - 1) + "…" : s
}

/* ---- status -> panel model ------------------------------------------------ */

/*
 * Build {running, groups, nodes, connectedKeys} from the manager's status.
 * Nodes are grouped by subscription (the synthetic "auto" node gets its own
 * group); `maxNodes` caps what the shell holds in memory.
 */
function groupsFromStatus(data, maxNodes, nowSec) {
  var result = { running: false, groups: [], nodes: [], connectedKeys: {} }
  if (!data || typeof data !== "object") return result
  result.running = data.running === true
  var cap = maxNodes || 1000
  var raw = data.nodes || []
  var connected = result.running ? String(data.connectedKey || "") : ""
  if (connected !== "") result.connectedKeys[connected] = true

  var subs = data.subs || []
  var bySub = {}
  var order = []
  for (var i = 0; i < raw.length && result.nodes.length < cap; i++) {
    var src = raw[i] || {}
    var node = {
      key: String(src.key || ""),
      name: String(src.name || "Unnamed"),
      address: String(src.address || ""),
      net: String(src.net || ""),
      latency: String(src.latency || ""),
      sub: typeof src.sub === "number" ? src.sub : 0
    }
    if (node.key === "") continue
    node.connected = connected !== "" && node.key === connected
    result.nodes.push(node)
    var gk = node.key === "auto" ? "auto" : String(node.sub)
    if (bySub[gk] === undefined) { bySub[gk] = []; order.push(gk) }
    bySub[gk].push(node)
  }
  for (var g = 0; g < order.length; g++) {
    var k = order[g]
    var title = "AUTO"
    var status = ""
    if (k !== "auto") {
      var sub = subs[parseInt(k, 10)] || {}
      title = String(sub.title || sub.host || "SERVERS").toUpperCase()
      status = subInfoLabel(sub.info, nowSec)
    }
    result.groups.push({ title: title, status: status, subscriptionId: k, nodes: bySub[k] })
  }
  return result
}

/* "12.3 GB / 100 GB · 23d left" from subscription-userinfo. */
function subInfoLabel(info, nowSec) {
  if (!info || typeof info !== "object") return ""
  var parts = []
  var used = (Number(info.upload) || 0) + (Number(info.download) || 0)
  var total = Number(info.total) || 0
  if (total > 0) parts.push(formatBytes(used) + " / " + formatBytes(total))
  else if (used > 0) parts.push(formatBytes(used) + " used")
  var expire = Number(info.expire) || 0
  if (expire > 0) {
    var now = nowSec || Math.floor(Date.now() / 1000)
    var days = Math.floor((expire - now) / 86400)
    parts.push(days < 0 ? "expired" : (days === 0 ? "expires today" : days + "d left"))
  }
  return parts.join(" · ")
}

function skippedLabel(skipped) {
  if (!skipped || typeof skipped !== "object") return ""
  var total = 0
  var top = ""
  var topN = 0
  for (var reason in skipped) {
    var n = Number(skipped[reason]) || 0
    total += n
    if (n > topN) { topN = n; top = reason }
  }
  if (total === 0) return ""
  return total + (total === 1 ? " node" : " nodes") + " skipped (" + elide(top, 80) + (total > topN ? ", …" : "") + ")"
}

/* ---- xray metrics (/debug/vars) -> traffic ---------------------------------- */

/*
 * Sums every inbound's counters (socks, http and tun) and derives speeds
 * against the previous sample. Also picks the balancer's current best
 * outbound from the observatory (alive, lowest delay).
 */
function parseMetrics(vars, prev, nowMs) {
  var out = { upTotal: 0, downTotal: 0, upSpeed: 0, downSpeed: 0, t: nowMs || 0, autoPick: "" }
  if (!vars || typeof vars !== "object") return null
  var inbound = (vars.stats && vars.stats.inbound) || {}
  for (var tag in inbound) {
    var c = inbound[tag] || {}
    out.upTotal += Number(c.uplink) || 0
    out.downTotal += Number(c.downlink) || 0
  }
  if (prev && prev.t > 0 && out.t > prev.t) {
    var dt = (out.t - prev.t) / 1000
    if (dt > 0.4 && out.upTotal >= prev.upTotal && out.downTotal >= prev.downTotal) {
      out.upSpeed = Math.round((out.upTotal - prev.upTotal) / dt)
      out.downSpeed = Math.round((out.downTotal - prev.downTotal) / dt)
    }
  }
  var obs = vars.observatory
  if (obs && typeof obs === "object") {
    var best = -1
    for (var ob in obs) {
      var s = obs[ob] || {}
      var d = Number(s.delay) || 0
      if (s.alive === true && (best < 0 || d < best)) { best = d; out.autoPick = ob }
    }
  }
  return out
}

/* ---- node helpers ----------------------------------------------------------- */

function latencyLabel(raw) {
  var s = String(raw || "").trim()
  if (s === "") return ""
  if (/ms$/i.test(s)) return s
  if (/^timeout$/i.test(s)) return "timeout"
  if (/time/i.test(s) || /fail/i.test(s) || /error/i.test(s) || /refus/i.test(s) || /unreachable/i.test(s)) return "unreach"
  return elide(s, 18)
}

function latencyGood(label) {
  var m = /^(\d+)ms$/.exec(String(label || ""))
  return m !== null && parseInt(m[1], 10) < 400
}

function latencyBad(label) {
  var l = String(label || "")
  return l === "timeout" || l === "unreach"
}

function filterNodes(groups, query) {
  var q = String(query || "").trim().toLowerCase()
  if (q === "") return groups
  var out = []
  for (var g = 0; g < groups.length; g++) {
    var src = groups[g]
    var kept = []
    for (var i = 0; i < src.nodes.length; i++) {
      var n = src.nodes[i]
      var hay = (n.name + " " + n.address + " " + n.net + " " + src.title).toLowerCase()
      if (hay.indexOf(q) !== -1) kept.push(n)
    }
    if (kept.length > 0) out.push({ title: src.title, subscriptionId: src.subscriptionId, status: src.status, nodes: kept })
  }
  return out
}

function findNodeByKey(nodes, key) {
  if (!key) return null
  for (var i = 0; i < nodes.length; i++) if (nodes[i].key === key) return nodes[i]
  return null
}

function pickConnectTarget(state, lastKey) {
  var nodes = (state && state.nodes) || []
  var byLast = findNodeByKey(nodes, lastKey)
  if (byLast) return byLast
  for (var i = 0; i < nodes.length; i++) if (nodes[i].connected) return nodes[i]
  for (var j = 0; j < nodes.length; j++) if (nodes[j].key !== "auto") return nodes[j]
  return nodes.length > 0 ? nodes[0] : null
}

/* Display name of the balancer's current pick ("" when unknown). */
function autoPickName(autoMembers, nodes, tag) {
  if (!tag) return ""
  var members = autoMembers || []
  for (var i = 0; i < members.length; i++) {
    if (members[i].tag === tag) {
      var n = findNodeByKey(nodes || [], members[i].key)
      return n ? n.name : ""
    }
  }
  return ""
}

/* ---- formatting ------------------------------------------------------------- */

function formatSpeed(bytesPerSec) {
  var b = Number(bytesPerSec) || 0
  if (b <= 0) return "0 B/s"
  if (b < 1024) return Math.round(b) + " B/s"
  if (b < 1048576) return (b / 1024).toFixed(1) + " KB/s"
  if (b < 1073741824) return (b / 1048576).toFixed(1) + " MB/s"
  return (b / 1073741824).toFixed(2) + " GB/s"
}

function formatBytes(n) {
  var b = Number(n) || 0
  if (b <= 0) return "0 B"
  if (b < 1024) return Math.round(b) + " B"
  if (b < 1048576) return (b / 1024).toFixed(1) + " KB"
  if (b < 1073741824) return (b / 1048576).toFixed(1) + " MB"
  return (b / 1073741824).toFixed(2) + " GB"
}

function heroLine(state) {
  if (!state) return "…"
  if (state.unreachable) return "Xray manager unreachable"
  var t = state.touch
  if (!t) return "Checking…"
  var keys = t.connectedKeys || {}
  var connectedName = ""
  var connectedKey = ""
  for (var i = 0; i < t.nodes.length; i++) {
    if (keys[t.nodes[i].key] === true) { connectedName = t.nodes[i].name; connectedKey = t.nodes[i].key; break }
  }
  var mode = state.mode === "tun" ? " (TUN)" : ""
  if (connectedName !== "") {
    if (connectedKey === "auto") return "Connected" + mode + " · Auto" + (state.autoPick ? " → " + state.autoPick : "")
    return "Connected" + mode + " · " + connectedName
  }
  if (t.running) return "Core running · not connected"
  return "Disconnected"
}
