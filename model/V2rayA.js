.pragma library

/*
 * Pure logic for talking to a local v2rayA daemon over its REST API.
 *
 * Everything here is plain ES5 JavaScript so tests/run.js can load this file
 * under Node without a QML engine. The QML side only supplies curl plumbing.
 *
 * API contract (verified against v2rayA service/server/router/index.go):
 *   envelope:  {code: "SUCCESS"|"FAIL", message: string|null, data: ...}
 *   login:     POST /api/login {username,password} -> data.token
 *   state:     GET /api/touch -> data {running, networkPaused, touch:{servers,
 *              subscriptions:[{id,servers[]}], connectedServer:[Which]}}
 *   connect:   POST /api/connection   body = Which {_type,id,sub,outbound}
 *   disconnect: DELETE /api/connection (same body)
 *   core:      POST /api/v2ray (start) / DELETE /api/v2ray (stop)
 *   latency:   GET /api/httpLatency?whiches=<urlencoded json array>
 *   subs:      PUT /api/subscription body = Which {_type:"subscription",id}
 *   import:    POST /api/import {url}
 *   first run: GET /api/account (no auth) -> data.hasAnyAccounts
 */

var DEFAULT_TIMEOUT_SEC = 10
var MARK_RC = "__V2A_RC__"

function shellQuote(value) {
  var s = String(value === undefined || value === null ? "" : value)
  if (s === "") return "''"
  return "'" + s.replace(/'/g, "'\\''") + "'"
}

function trimSlash(path) {
  var p = String(path || "")
  while (p.length > 1 && p.charAt(p.length - 1) === "/") p = p.substring(0, p.length - 1)
  return p.charAt(0) === "/" ? p : "/" + p
}

/*
 * Builds the bash script for one API call. The response is emitted with two
 * trailing marker lines so parseResponse can recover body, HTTP status and
 * exit code even when stderr noise got merged in.
 */
function curlScript(opts) {
  var o = opts || {}
  var parts = ["curl", "-sS", "--max-time", String(o.timeoutSec || DEFAULT_TIMEOUT_SEC)]
  var socket = String(o.socketPath || "")
  if (socket !== "") {
    parts.push("--unix-socket")
    parts.push(shellQuote(socket))
  }
  parts.push("-X")
  parts.push(String(o.method || "GET").toUpperCase())
  var token = String(o.token || "")
  if (token !== "") {
    parts.push("-H")
    parts.push(shellQuote("Authorization: Bearer " + token))
  }
  var body = o.body
  if (body !== undefined && body !== null && body !== "") {
    parts.push("-H")
    parts.push("'Content-Type: application/json'")
    parts.push("--data")
    parts.push(shellQuote(typeof body === "string" ? body : JSON.stringify(body)))
  }
  parts.push("-w")
  parts.push("'\\n" + "%{http_code}" + "'")
  parts.push(shellQuote(String(o.url || "")))
  var script = "out=$(" + parts.join(" ") + " 2>&1); rc=$?; printf '%s\\n" + MARK_RC + "%s' \"$out\" \"$rc\""
  return script
}

function parseResponse(raw) {
  var text = String(raw === undefined || raw === null ? "" : raw)
  var out = { ok: false, exit: -1, httpStatus: 0, data: null, message: "", unauthorized: false, reachable: false }

  var rcIdx = text.lastIndexOf("\n" + MARK_RC)
  if (rcIdx < 0) {
    out.message = text.trim() !== "" ? text.trim().substring(0, 200) : "no output from curl"
    return out
  }
  out.exit = parseInt(text.substring(rcIdx + MARK_RC.length + 1), 10)
  if (!isFinite(out.exit)) out.exit = -1
  var rest = text.substring(0, rcIdx)

  var nl = rest.lastIndexOf("\n")
  var statusLine = nl >= 0 ? rest.substring(nl + 1) : rest
  var body = nl >= 0 ? rest.substring(0, nl) : ""
  var code = parseInt(statusLine, 10)
  out.httpStatus = isFinite(code) ? code : 0
  out.reachable = out.exit === 0 && out.httpStatus > 0

  if (out.exit !== 0) {
    out.message = summarizeCurlError(body, out.exit)
    return out
  }
  if (out.httpStatus === 401) {
    out.unauthorized = true
    out.message = extractFailMessage(body) || "unauthorized"
    return out
  }
  if (out.httpStatus < 200 || out.httpStatus >= 300) {
    out.message = extractFailMessage(body) || ("HTTP " + out.httpStatus)
    return out
  }

  var parsed = safeParseJson(body)
  if (parsed === null || typeof parsed !== "object") {
    out.message = "unexpected response from v2rayA"
    return out
  }
  if (parsed.code === "SUCCESS") {
    out.ok = true
    out.data = parsed.data
    return out
  }
  out.message = parsed.message || parsed.code || "v2rayA request failed"
  if (out.httpStatus === 401) out.unauthorized = true
  return out
}

/* JSON.parse that survives interleaved stderr noise: falls back to the
 * outermost {...} span of the text. */
function safeParseJson(text) {
  try { return JSON.parse(text) } catch (e) {}
  var start = text.indexOf("{")
  var end = text.lastIndexOf("}")
  if (start === -1 || end <= start) return null
  try { return JSON.parse(text.substring(start, end + 1)) } catch (e) { return null }
}

function extractFailMessage(body) {
  var parsed = safeParseJson(body)
  if (parsed && typeof parsed === "object") {
    if (typeof parsed.message === "string" && parsed.message !== "") return elide(parsed.message, 160)
    if (parsed.data && typeof parsed.data.first === "boolean") return "first-run: no v2rayA account exists yet"
  }
  return ""
}

function summarizeCurlError(body, exitCode) {
  var lines = String(body || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i].trim()
    if (/^curl: \(\d+\)/.test(line)) {
      if (/curl: \(7\)/.test(line)) return "v2rayA is not reachable (connection refused)"
      if (/curl: \(28\)/.test(line)) return "v2rayA timed out"
      return elide(line, 160)
    }
  }
  if (exitCode === 7) return "v2rayA is not reachable (connection refused)"
  if (exitCode === 28) return "v2rayA timed out"
  return "curl failed with exit code " + exitCode
}

function elide(s, n) {
  s = String(s || "")
  return s.length > n ? s.substring(0, n - 1) + "…" : s
}

/* ---- Which helpers ------------------------------------------------------ */

function whichKey(w) {
  if (!w) return ""
  var type = String(w._type || "")
  if (type === "subscriptionServer") return "ss:" + w.sub + ":" + w.id
  if (type === "server") return "s:" + w.id
  if (type === "subscription") return "sub:" + w.id
  return ""
}

function serverKey(server, subIndex) {
  if (subIndex === null || subIndex === undefined) return "s:" + server.id
  return "ss:" + subIndex + ":" + server.id
}

function whichFor(server, subIndex, outbound) {
  var w = { _type: subIndex === null || subIndex === undefined ? "server" : "subscriptionServer",
            id: server.id,
            outbound: outbound || "proxy" }
  if (subIndex !== null && subIndex !== undefined) w.sub = subIndex
  return w
}

/* Touch row -> display node */
function toNode(server, subIndex) {
  var key = serverKey(server, subIndex)
  return {
    key: key,
    name: String(server.name || "Unnamed"),
    address: String(server.address || ""),
    net: String(server.net || ""),
    latency: String(server.pingLatency || ""),
    which: whichFor(server, subIndex)
  }
}

/*
 * Flatten GET /api/touch into UI-friendly groups plus connected keys.
 * Returns {running, networkPaused, groups, nodes, connectedKeys, connectedNames}
 */
function parseTouch(data) {
  var result = { running: false, networkPaused: false, groups: [], nodes: [], connectedKeys: {}, connectedNames: [] }
  if (!data || typeof data !== "object") return result
  result.running = data.running === true
  result.networkPaused = data.networkPaused === true
  var t = data.touch || {}

  var connected = t.connectedServer || []
  for (var c = 0; c < connected.length; c++) {
    var w = connected[c] || {}
    var k = whichKey(w)
    if (k !== "") {
      result.connectedKeys[k] = true
      result.connectedNames.push(String(w._type === "subscription" ? ("subscription #" + w.id) : ("#" + w.id)))
    }
  }

  var standalone = t.servers || []
  if (standalone.length > 0) {
    var g = { title: "SERVERS", nodes: [] }
    for (var i = 0; i < standalone.length; i++) {
      var n = toNode(standalone[i], null)
      n.connected = result.connectedKeys[n.key] === true
      g.nodes.push(n)
    }
    result.groups.push(g)
    result.nodes = result.nodes.concat(g.nodes)
  }

  var subs = t.subscriptions || []
  for (var s = 0; s < subs.length; s++) {
    var sub = subs[s] || {}
    var title = String(sub.remarks || sub.host || ("subscription #" + (sub.id || s + 1)))
    var sg = { title: title.toUpperCase(), subscriptionId: sub.id, status: String(sub.status || ""), nodes: [] }
    var servers = sub.servers || []
    for (var j = 0; j < servers.length; j++) {
      var sn = toNode(servers[j], s)
      sn.subscriptionId = sub.id
      sn.connected = result.connectedKeys[sn.key] === true
      sg.nodes.push(sn)
    }
    result.groups.push(sg)
    result.nodes = result.nodes.concat(sg.nodes)
  }
  return result
}

function applyLatencies(touchResult, cache) {
  if (!touchResult || !cache) return touchResult
  for (var i = 0; i < touchResult.nodes.length; i++) {
    var n = touchResult.nodes[i]
    var cached = cache[n.key]
    if (typeof cached === "string" && cached !== "") n.latency = cached
  }
  return touchResult
}

/* Merge httpLatency results into the local cache. Returns a new cache object. */
function mergeLatencies(cache, returnedWhiches) {
  var next = {}
  for (var k in (cache || {})) next[k] = cache[k]
  var list = returnedWhiches || []
  for (var i = 0; i < list.length; i++) {
    var w = list[i]
    if (!w) continue
    next[whichKey(w)] = String(w.pingLatency || "")
  }
  return next
}

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

/*
 * Build the urlencoded `whiches` query value for /api/httpLatency.
 * Caps at maxNodes so testing a huge subscription cannot hammer the network.
 */
function buildLatencyQuery(nodes, maxNodes, testUrl) {
  var list = []
  var cap = maxNodes || 100
  for (var i = 0; i < nodes.length && list.length < cap; i++) {
    var w = nodes[i] && nodes[i].which
    if (w) list.push({ _type: w._type, id: w.id, sub: w.sub, outbound: w.outbound })
  }
  var q = "whiches=" + encodeURIComponent(JSON.stringify(list))
  var tu = String(testUrl || "").trim()
  if (tu !== "") q += "&testUrl=" + encodeURIComponent(tu)
  return q
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
      var hay = (n.name + " " + n.address + " " + src.title).toLowerCase()
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
  return nodes.length > 0 ? nodes[0] : null
}

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
  if (state.unreachable) return "v2rayA unreachable"
  if (state.firstRun) return "No v2rayA account — open web UI"
  if (state.needsCredentials) return "Set v2rayA login in widget settings"
  var connectedName = ""
  if (state.touch) {
    var keys = state.touch.connectedKeys || {}
    for (var i = 0; i < state.touch.nodes.length; i++) {
      if (keys[state.touch.nodes[i].key] === true) { connectedName = state.touch.nodes[i].name; break }
    }
  }
  if (state.touch && Object.keys(keys).length > 0 && connectedName !== "") {
    return "Connected · " + connectedName
  }
  if (state.touch && state.touch.running) return "Core running · not connected"
  return state.touch ? "Disconnected" : "Checking…"
}
