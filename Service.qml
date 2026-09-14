import QtQuick
import Quickshell
import Quickshell.Io
import "model/V2rayA.js" as V2rayA

/*
 * Backend: the omarchy-xray manager (~/.local/bin/omarchy-xray) which drives a
 * systemd user service running /usr/bin/xray with a generated config.
 * Every call is a plain subprocess with JSON on stdout — no auth, no REST.
 */
Item {
  id: root

  property var settings: ({})
  property var panelRef: null
  property bool panelOpen: false

  // --- observable state ---------------------------------------------------
  property bool reachable: false        // manager answered
  property bool installed: true         // omarchy-xray found on PATH
  property string lastError: ""
  property string actionStatus: ""
  property var touch: null              // manager status.touch (same shape as before)
  property var traffic: null            // manager stats (upTotal/downTotal/speeds)
  property string mode: "proxy"
  property var subs: []

  readonly property int connectedCount: touch !== null ? Object.keys(touch.connectedKeys || {}).length : 0
  readonly property bool connected: connectedCount > 0
  readonly property bool coreRunning: touch !== null && touch.running === true

  readonly property string connectedNodeName: {
    if (!touch || connectedCount === 0) return ""
    for (var i = 0; i < touch.nodes.length; i++)
      if (touch.connectedKeys[touch.nodes[i].key] === true) return touch.nodes[i].name
    return ""
  }

  readonly property string heroSummary: V2rayA.heroLine({
    unreachable: !reachable,
    firstRun: false,
    needsCredentials: false,
    touch: touch
  })

  readonly property int refreshIntervalSec: intSetting("refreshIntervalSec", 20, 10, 600)
  readonly property string barLabel: strSetting("barLabel", "speed")

  // Hardening bounds: stdout cap (bytes), node cap for rendering, input caps.
  readonly property int outCap: 524288
  readonly property int maxNodes: 1000
  readonly property int maxInput: 2048

  function setting(name, fallback) {
    var value = settings ? settings[name] : undefined
    return value === undefined || value === null ? fallback : value
  }

  function intSetting(name, fallback, min, max) {
    var n = parseInt(String(setting(name, fallback)), 10)
    if (!isFinite(n)) n = fallback
    if (n < min) n = min
    if (n > max) n = max
    return n
  }

  function strSetting(name, fallback) {
    var v = String(setting(name, fallback))
    return v.trim()
  }

  readonly property bool busy: _action.running || _long.running || _stats.running

  // --- plumbing -----------------------------------------------------------

  // Secret hygiene: redact any scheme://…@ credential before it can reach
  // status text, error labels or logs. Subscription hosts are not secrets,
  // but full URLs (path/query tokens) never leave the manager.
  function scrub(s) {
    return String(s === undefined || s === null ? "").replace(/[a-zA-Z][a-zA-Z0-9+.-]*:\/\/\S+@\S+/g, function(m) {
      var scheme = m.substring(0, m.indexOf("://"))
      var host = m.substring(m.lastIndexOf("@") + 1)
      return scheme + "://" + host + "/***"
    })
  }

  function boundedArgs(args) {
    var out = []
    for (var i = 0; i < args.length; i++) {
      var a = String(args[i])
      if (a.length > maxInput) return null
      out.push(a)
    }
    return out
  }

  // Wrap StdioCollector text so one runaway dump cannot freeze the shell:
  // take the last outCap chars and, failing a JSON parse, the outermost {}.
  function takeTail(text) {
    var s = String(text || "")
    if (s.length > outCap) s = s.substring(s.length - outCap)
    return s
  }

  function extractJson(text) {
    var s = takeTail(text)
    try { return JSON.parse(s) } catch (e) {}
    // Manager may print warn/progress lines on stdout: fall back to the
    // outermost {...} span instead of rejecting the whole payload.
    var start = s.indexOf("{")
    var end = s.lastIndexOf("}")
    if (start >= 0 && end > start) {
      try { return JSON.parse(s.substring(start, end + 1)) } catch (e2) {}
    }
    return null
  }

  function run(slot, args, done, env) {
    if (slot.running) return false
    var bounded = boundedArgs(args)
    if (bounded === null) {
      lastError = "Input too long — refused"
      return false
    }
    slot._done = done
    if (env !== undefined) slot.environment = env
    slot.command = bounded
    slot.running = true
    return true
  }

  function finish(slot, stdoutText, exitCode) {
    var done = slot._done
    slot._done = null
    var parsed = extractJson(stdoutText)
    var resp = { ok: parsed !== null && parsed.ok !== false, data: parsed,
                 message: parsed && parsed.error ? scrub(parsed.error) : "" }
    if (exitCode !== 0 && resp.message === "") resp.message = "omarchy-xray exited with code " + exitCode
    reachable = true
    installed = true
    if (done) done(resp)
    return resp
  }

  // Per-slot deadline + whole-child reaping: the slot timer kills a hung
  // run (its process group dies with it) and surfaces a visible error.
  function armDeadline(slot, timer, ms, label) {
    slot._label = label
    timer.interval = ms
    timer.restart()
  }

  function onDeadline(slot, timer) {
    timer.stop()
    if (!slot.running) return
    slot.running = false
    try { slot.signal(9) } catch (e) {}
    try { slot.environment = ({}) } catch (e2) {}
    slot._done = null
    reachable = true
    installed = true
    lastError = scrub(labelOf(slot) + " timed out — killed")
    actionStatus = ""
    refresh()
  }

  function labelOf(slot) {
    return String(slot._label || "omarchy-xray")
  }

  function managerFail(message) {
    reachable = false
    installed = false
    lastError = "Xray manager not found — reinstall the widget (./install.sh)"
    if (message !== "") lastError = message
  }

  // --- actions ------------------------------------------------------------

  function refresh() {
    if (!run(_action, ["omarchy-xray", "status"], applyStatusAndStop)) return
    else armDeadline(_action, _actionDeadline, 30000, "status")
  }

  // Shared _action callback for status: stops the deadline, then applies.
  function applyStatusAndStop(resp) {
    _actionDeadline.stop()
    applyStatus(resp)
  }

  function applyStatus(resp) {
    if (!resp.ok || !resp.data || !resp.data.touch) {
      if (resp.message !== "") { reachable = false; lastError = scrub(resp.message); installed = false }
      return
    }
    reachable = true
    installed = true
    lastError = ""
    mode = String(resp.data.mode || "proxy")
    // Bounded serialization: cap the node array the shell holds in memory.
    var rawSubs = resp.data.subs || []
    subs = rawSubs.slice ? rawSubs.slice(0, 64) : rawSubs
    var t = resp.data.touch || null
    if (t && t.nodes && t.nodes.length > maxNodes) {
      var cut = { running: t.running, groups: [], nodes: t.nodes.slice(0, maxNodes), connectedKeys: {} }
      var kept = {}
      for (var k = 0; k < cut.nodes.length; k++) kept[cut.nodes[k].key] = true
      var srcKeys = t.connectedKeys || {}
      for (var key in srcKeys) if (kept[key] === true) cut.connectedKeys[key] = true
      for (var g = 0; g < (t.groups || []).length && cut.nodes.length > 0; g++) {
        var gn = []
        for (var n = 0; n < t.groups[g].nodes.length; n++)
          if (kept[t.groups[g].nodes[n].key] === true) gn.push(t.groups[g].nodes[n])
        if (gn.length > 0) cut.groups.push({ title: t.groups[g].title, status: t.groups[g].status, nodes: gn })
      }
      t = cut
    }
    touch = t
  }

  function connectNode(node) {
    if (!node || !node.key) return
    if (String(node.key).length > 64) { lastError = "Bad node key — refused"; return }
    if (!run(_action, ["omarchy-xray", "select", node.key], function(resp) {
      _actionDeadline.stop()
      if (!resp.ok) { lastError = "Select failed: " + (resp.message || "?"); return }
      actionStatus = "Switched to " + scrub(node.name)
      actionStatusTimer.restart()
      persistLastNode(node.key)
      if (!coreRunning) cmdOn()
      else refresh()
    })) { busyRefused(); return }
    else armDeadline(_action, _actionDeadline, 30000, "select")
  }

  function disconnect() {
    if (!run(_action, ["omarchy-xray", "off"], function(resp) {
      _actionDeadline.stop()
      if (resp.ok) { actionStatus = "Disconnected"; actionStatusTimer.restart() }
      else lastError = "Disconnect failed: " + (resp.message || "?")
      refresh()
    })) { busyRefused(); return }
    else armDeadline(_action, _actionDeadline, 60000, "disconnect")
  }

  function cmdOn() {
    if (!run(_action, ["omarchy-xray", "on"], function(resp) {
      _actionDeadline.stop()
      if (!resp.ok) lastError = "Start failed: " + (resp.message || "?")
      else { actionStatus = "Connected"; actionStatusTimer.restart() }
      refresh()
    })) { busyRefused(); return }
    else armDeadline(_action, _actionDeadline, 90000, "start")
  }

  function toggleConnection(lastKey) {
    if (connected) { disconnect(); return }
    var target = V2rayA.pickConnectTarget(touch || {}, lastKey)
    if (target === null) { lastError = "No nodes yet — add a subscription URL in the panel"; return }
    connectNode(target)
  }

  function startCore() { cmdOn() }

  function stopCore() { disconnect() }

  function testNodes(nodes) {
    if (!installed) return
    var list = nodes || []
    if (list.length > maxNodes) list = list.slice(0, maxNodes)
    if (!run(_long, ["omarchy-xray", "test"], function(resp) {
      _longDeadline.stop()
      if (resp.ok) { actionStatus = "Latency test done"; actionStatusTimer.restart() }
      else { actionStatus = ""; lastError = "Test failed: " + (resp.message || "?") }
      refresh()
    })) { busyRefused(); return }
    actionStatus = "Testing nodes (max " + maxNodes + ", 10 min cap)…"
    armDeadline(_long, _longDeadline, 660000, "latency test")
  }

  function updateSubscriptions() {
    if (!run(_long, ["omarchy-xray", "update"], function(resp) {
      _longDeadline.stop()
      if (resp.ok) { actionStatus = "Subscriptions updated"; actionStatusTimer.restart() }
      else { actionStatus = ""; lastError = "Update failed: " + (resp.message || "?") }
      refresh()
    })) { busyRefused(); return }
    actionStatus = "Updating subscription…"
    armDeadline(_long, _longDeadline, 180000, "subscription update")
  }

  function importUrl(url) {
    // The URL field is a secret: refuse absurd lengths, pass it via the
    // process environment (never argv — argv is world-visible via ps).
    var u = String(url || "").trim()
    if (u === "") return
    if (u.length > maxInput) { lastError = "URL too long — refused"; return }
    if (!/^https:\/\//i.test(u)) { lastError = "Subscription URL must be https://…"; return }
    if (!run(_long, ["omarchy-xray", "import", "-"], function(resp) {
      _longDeadline.stop()
      _long.environment = ({})
      if (resp.ok) { actionStatus = "Imported"; actionStatusTimer.restart() }
      else { actionStatus = ""; lastError = "Import failed: " + (resp.message || "?") }
      refresh()
    }, { OMARCHY_XRAY_SUB_URL: u })) { busyRefused(); return }
    actionStatus = "Importing…"
    armDeadline(_long, _longDeadline, 180000, "import")
  }

  function openWebUi() {
    Quickshell.execDetached(["xdg-open", Quickshell.env("HOME") + "/.config/omarchy-xray"])
  }

  function pollStats() {
    if (!installed || _stats.running) return
    run(_stats, ["omarchy-xray", "stats"], function(resp) {
      _statsDeadline.stop()
      if (resp.ok && resp.data && resp.data.running !== false) traffic = resp.data
      else traffic = null
    })
    armDeadline(_stats, _statsDeadline, 20000, "stats")
  }

  function setMode(mode) {
    if (!installed || _long.running) return
    if (mode !== "proxy" && mode !== "tun") { lastError = "Bad mode — refused"; return }
    actionStatus = mode === "tun" ? "Switching to TUN — confirm the polkit prompt (or: sudo omarchy-xray route-up)…" : "Switching to proxy…"
    run(_long, ["omarchy-xray", "mode", mode], function(resp) {
      _longDeadline.stop()
      if (resp.ok) { actionStatus = "Mode: " + mode; actionStatusTimer.restart() }
      else { actionStatus = ""; lastError = "Mode switch failed: " + (resp.message || "?") }
      refresh()
    })
    armDeadline(_long, _longDeadline, 180000, "mode switch")
  }

  function subRemove(url) {
    if (!installed || _long.running) return
    // Manager matches by host/index — the full URL (token) never goes on argv.
    var key = String(url || "")
    var host = key
    var m = /:\/\/([^/?#@]+@)?([^/?#:]+)/.exec(key)
    if (m) host = m[2]
    host = host.trim().substring(0, 253)
    if (host === "") return
    run(_long, ["omarchy-xray", "subremove", host], function(resp) {
      _longDeadline.stop()
      if (!resp.ok) lastError = "Remove failed: " + (resp.message || "?")
      refresh()
    })
    armDeadline(_long, _longDeadline, 120000, "subscription remove")
  }

  function persistLastNode(key) {
    if (panelRef && typeof panelRef.persistSetting === "function") panelRef.persistSetting("lastNodeKey", key)
  }

  function busyRefused() {
    actionStatus = "Previous command still running…"
    actionStatusTimer.restart()
  }

  // --- timers / processes -------------------------------------------------

  Timer {
    id: refreshTimer
    interval: root.refreshIntervalSec * 1000
    repeat: true
    running: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  Timer {
    interval: 2000
    repeat: true
    running: root.panelOpen
    onTriggered: root.refresh()
  }

  Timer {
    id: statsTimer
    interval: 2000
    repeat: true
    running: root.panelOpen || root.barLabel === "speed"
    triggeredOnStart: true
    onTriggered: root.pollStats()
  }

  Timer {
    id: actionStatusTimer
    interval: 2400
    repeat: false
    onTriggered: root.actionStatus = ""
  }

  // Hard per-slot deadlines: a hung manager run is SIGKILLed and surfaced
  // instead of wedging the panel. _long's watchdog is gone — each caller
  // arms its own bound (60–660 s depending on the operation).
  Timer {
    id: _actionDeadline
    interval: 30000
    repeat: false
    onTriggered: root.onDeadline(_action, _actionDeadline)
  }

  Timer {
    id: _statsDeadline
    interval: 20000
    repeat: false
    onTriggered: root.onDeadline(_stats, _statsDeadline)
  }

  Timer {
    id: _longDeadline
    interval: 180000
    repeat: false
    onTriggered: root.onDeadline(_long, _longDeadline)
  }

  Process {
    id: _action
    property var _done: null
    running: false
    command: []
    stdout: StdioCollector { id: actionStdout; waitForEnd: true }
    stderr: StdioCollector { id: actionStderr; waitForEnd: true }
    onExited: function(exitCode) {
      var out = String(actionStdout.text || "")
      if (out.trim() === "") {
        root.managerFail(String(actionStderr.text || "").trim())
        _action._done = null
        return
      }
      root.finish(_action, out, exitCode)
    }
  }

  Process {
    id: _stats
    property var _done: null
    running: false
    command: []
    stdout: StdioCollector { id: statsStdout; waitForEnd: true }
    stderr: StdioCollector { waitForEnd: true }
    onExited: function(exitCode) {
      var out = String(statsStdout.text || "")
      if (out.trim() === "") { _stats._done = null; return }
      root.finish(_stats, out, exitCode)
    }
  }

  Process {
    id: _long
    property var _done: null
    running: false
    command: []
    stdout: StdioCollector { id: longStdout; waitForEnd: true }
    stderr: StdioCollector { id: longStderr; waitForEnd: true }
    onExited: function(exitCode) {
      var out = String(longStdout.text || "")
      if (out.trim() === "") {
        root.finish(_long, '{"ok":false,"error":"omarchy-xray produced no output"}', exitCode)
        return
      }
      root.finish(_long, out, exitCode)
    }
  }
}
