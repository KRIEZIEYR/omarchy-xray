import QtQuick
import Quickshell
import Quickshell.Io
import "model/Xray.js" as Model

/*
 * Backend: the omarchy-xray manager (~/.local/bin/omarchy-xray). Proxy mode
 * runs xray as a systemd user unit, TUN mode as the omarchy-xray-tun system
 * unit (one-time `tun-setup`). Every call is a plain subprocess with JSON on
 * stdout; traffic comes straight from xray's loopback metrics endpoint.
 */
Item {
  id: root

  property var settings: ({})
  property var panelRef: null
  property bool panelOpen: false

  // --- observable state ---------------------------------------------------
  property bool reachable: false        // manager answered
  property bool installed: true         // manager found
  property string lastError: ""
  property string actionStatus: ""
  property var touch: null              // {running, groups, nodes, connectedKeys}
  property var traffic: null            // {upTotal, downTotal, upSpeed, downSpeed, autoPick}
  property string mode: "proxy"
  property string routing: "global"
  property bool adblock: false
  property bool geo: false
  property bool tunInstalled: false
  property var subs: []
  property string skippedText: ""
  property var autoMembers: []
  property string metricsUrl: "http://127.0.0.1:15491/debug/vars"
  property string _statusRaw: ""
  property real _lastAutoUpdate: 0

  readonly property int connectedCount: touch !== null ? Object.keys(touch.connectedKeys || {}).length : 0
  readonly property bool connected: connectedCount > 0
  readonly property bool coreRunning: touch !== null && touch.running === true
  readonly property string autoPickName: traffic ? Model.autoPickName(autoMembers, touch ? touch.nodes : [], traffic.autoPick) : ""

  readonly property string connectedNodeName: {
    if (!touch || connectedCount === 0) return ""
    for (var i = 0; i < touch.nodes.length; i++)
      if (touch.connectedKeys[touch.nodes[i].key] === true)
        return touch.nodes[i].key === "auto" && autoPickName !== "" ? autoPickName : touch.nodes[i].name
    return ""
  }

  readonly property string heroSummary: Model.heroLine({
    unreachable: !reachable,
    touch: touch,
    mode: mode,
    autoPick: autoPickName
  })

  readonly property int refreshIntervalSec: intSetting("refreshIntervalSec", 20, 10, 600)
  readonly property string barLabel: strSetting("barLabel", "speed")

  // Hardening bounds: stdout cap (bytes), node cap for rendering, input caps.
  readonly property int outCap: 524288
  readonly property int maxNodes: 1000
  readonly property int maxInput: 2048
  readonly property string manager: String(Quickshell.env("HOME") || "") + "/.local/bin/omarchy-xray"

  // Children start with a cleared environment; with clearEnvironment a null
  // value means "inherit this one variable from the shell".
  readonly property var baseEnv: ({
    HOME: null, USER: null, LOGNAME: null, LANG: null, PATH: null,
    XDG_RUNTIME_DIR: null, DBUS_SESSION_BUS_ADDRESS: null,
    WAYLAND_DISPLAY: null, DISPLAY: null
  })

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
    return String(setting(name, fallback)).trim()
  }

  readonly property bool busy: _action.running || _long.running

  // --- plumbing -----------------------------------------------------------

  // Secret hygiene: redact any scheme://…@ credential before it can reach
  // status text, error labels or logs.
  function scrub(s) {
    return String(s === undefined || s === null ? "" : s).replace(/[a-zA-Z][a-zA-Z0-9+.-]*:\/\/\S+@\S+/g, function(m) {
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

  function takeTail(text) {
    var s = String(text || "")
    if (s.length > outCap) s = s.substring(s.length - outCap)
    return s
  }

  // Tolerant JSON extraction: whole text, else the last {...} line, else the
  // outermost {...} span (progress lines may precede the JSON).
  function extractJson(text) {
    var s = takeTail(text).trim()
    if (s === "") return null
    try { return JSON.parse(s) } catch (e) {}
    var lines = s.split("\n")
    for (var i = lines.length - 1; i >= 0; i--) {
      var l = lines[i].trim()
      if (l.charAt(0) === "{") { try { return JSON.parse(l) } catch (e2) {} }
    }
    var start = s.indexOf("{")
    var end = s.lastIndexOf("}")
    if (start >= 0 && end > start) {
      try { return JSON.parse(s.substring(start, end + 1)) } catch (e3) {}
    }
    return null
  }

  function run(slot, args, done, extraEnv) {
    if (slot.running) return false
    var bounded = boundedArgs(args)
    if (bounded === null) {
      lastError = "Input too long — refused"
      return false
    }
    var env = {}
    for (var k in baseEnv) env[k] = null
    if (extraEnv) for (var x in extraEnv) env[x] = extraEnv[x]
    slot._done = done
    slot.environment = env
    slot.command = bounded
    slot.running = true
    return true
  }

  function finish(slot, stdoutText, stderrText, exitCode) {
    var done = slot._done
    slot._done = null
    try { slot.environment = ({}) } catch (e) {}
    var parsed = extractJson(stdoutText)
    if (parsed === null) parsed = extractJson(stderrText)
    if (parsed === null && (exitCode === 127 || exitCode === 126)) {
      managerFail("")
      return null
    }
    var resp = { ok: parsed !== null && parsed.ok !== false && exitCode === 0, data: parsed,
                 message: parsed && parsed.error ? scrub(parsed.error) : "" }
    if (!resp.ok && resp.message === "") {
      var tail = String(stderrText || "").trim().split("\n").pop()
      resp.message = scrub(tail !== "" ? tail : "omarchy-xray exited with code " + exitCode)
    }
    reachable = true
    installed = true
    if (done) done(resp)
    return resp
  }

  // Per-slot deadline: the slot timer kills a hung run and surfaces an error.
  function armDeadline(slot, timer, ms, label) {
    slot._label = label
    timer.interval = ms
    timer.restart()
  }

  function onDeadline(slot, timer) {
    timer.stop()
    if (!slot.running) return
    slot._done = null
    try { slot.signal(9) } catch (e) {}
    slot.running = false
    try { slot.environment = ({}) } catch (e2) {}
    lastError = scrub(String(slot._label || "omarchy-xray") + " timed out — killed")
    actionStatus = ""
    refresh()
  }

  function managerFail(message) {
    reachable = false
    installed = false
    lastError = message !== "" ? message : "Xray manager not found — reinstall the widget (./install.sh)"
  }

  function flash(text) {
    actionStatus = text
    actionStatusTimer.restart()
  }

  function busyRefused() { flash("Previous command still running…") }

  // --- status -------------------------------------------------------------

  function refresh() {
    if (!run(_action, [manager, "status"], applyStatusAndStop)) return
    armDeadline(_action, _actionDeadline, 30000, "status")
  }

  function applyStatusAndStop(resp) {
    _actionDeadline.stop()
    applyStatus(resp)
  }

  function applyStatus(resp) {
    if (!resp.ok || !resp.data || !resp.data.nodes) {
      if (resp.message !== "") lastError = scrub(resp.message)
      return
    }
    var d = resp.data
    reachable = true
    installed = true
    mode = String(d.mode || "proxy")
    routing = String(d.routing || "global")
    adblock = d.adblock === true
    geo = d.geo === true
    tunInstalled = d.tunInstalled === true
    skippedText = Model.skippedLabel(d.skipped)
    autoMembers = d.autoMembers || []
    if (d.metricsUrl && /^http:\/\/127\.0\.0\.1:\d+\/debug\/vars$/.test(d.metricsUrl)) metricsUrl = d.metricsUrl
    lastError = d.lastError ? "Service failed: " + scrub(d.lastError) : (d.xray === false ? "xray core not found — install it (omarchy pkg aur add xray)" : "")
    var rawSubs = d.subs || []
    subs = rawSubs.slice ? rawSubs.slice(0, 64) : []
    // Rebuild the node model only when something changed: reassigning `touch`
    // recreates every delegate, which the 2 s open-panel poll made visible.
    var raw = JSON.stringify([d.nodes, d.subs, d.connectedKey, d.running])
    if (raw !== _statusRaw || touch === null) {
      _statusRaw = raw
      touch = Model.groupsFromStatus(d, maxNodes, Math.floor(Date.now() / 1000))
    }
    if (d.updateDue === true && !busy && Date.now() - _lastAutoUpdate > 600000) {
      _lastAutoUpdate = Date.now()
      updateSubscriptions()
    }
  }

  // --- actions ------------------------------------------------------------

  function connectNode(node) {
    if (!node || !node.key) return
    if (String(node.key).length > 64) { lastError = "Bad node key — refused"; return }
    if (!run(_action, [manager, "select", node.key], function(resp) {
      _actionDeadline.stop()
      if (!resp.ok) { lastError = "Select failed: " + (resp.message || "?"); refresh(); return }
      flash("Switched to " + scrub(node.name))
      persistLastNode(node.key)
      if (!coreRunning) cmdOn()
      else refresh()
    })) { busyRefused(); return }
    armDeadline(_action, _actionDeadline, 60000, "select")
  }

  function disconnect() {
    if (!run(_action, [manager, "off"], function(resp) {
      _actionDeadline.stop()
      if (resp.ok) flash("Disconnected")
      else lastError = "Disconnect failed: " + (resp.message || "?")
      traffic = null
      refresh()
    })) { busyRefused(); return }
    armDeadline(_action, _actionDeadline, 60000, "disconnect")
  }

  function cmdOn() {
    if (!run(_action, [manager, "on"], function(resp) {
      _actionDeadline.stop()
      if (!resp.ok) lastError = "Start failed: " + (resp.message || "?")
      else flash(mode === "tun" ? "Connected (TUN)" : "Connected")
      refresh()
    })) { busyRefused(); return }
    armDeadline(_action, _actionDeadline, 120000, "start")
  }

  function toggleConnection(lastKey) {
    if (connected) { disconnect(); return }
    var target = Model.pickConnectTarget(touch || {}, lastKey)
    if (target === null) { lastError = "No nodes yet — add a subscription URL in the panel"; return }
    connectNode(target)
  }

  function startCore() { cmdOn() }

  function stopCore() { disconnect() }

  function runLong(args, label, deadlineMs, okText, busyText, extraEnv, after) {
    if (!installed && label !== "import") return
    if (!run(_long, args, function(resp) {
      _longDeadline.stop()
      if (resp.ok) flash(okText)
      else { actionStatus = ""; lastError = label.charAt(0).toUpperCase() + label.substring(1) + " failed: " + (resp.message || "?") }
      if (after) after(resp)
      refresh()
    }, extraEnv)) { busyRefused(); return }
    actionStatus = busyText
    armDeadline(_long, _longDeadline, deadlineMs, label)
  }

  function testNodes(nodes) {
    var list = nodes || []
    var args = [manager, "test"]
    if (list.length === 1 && list[0].key && list[0].key !== "auto") args.push(list[0].key)
    runLong(args, "latency test", 660000, "Latency test done",
            args.length > 2 ? "Testing " + scrub(list[0].name) + "…" : "Testing nodes (batched, 10 min cap)…")
  }

  function testNode(node) { if (node) testNodes([node]) }

  function updateSubscriptions() {
    runLong([manager, "update"], "update", 240000, "Subscriptions updated", "Updating subscriptions…")
  }

  function updateSub(index) {
    var i = parseInt(index, 10)
    if (!isFinite(i) || i < 0 || i > 63) return
    runLong([manager, "update", String(i)], "update", 180000, "Subscription updated", "Updating subscription…")
  }

  function importUrl(url) {
    // The URL is a secret: bounded, https-only, passed via the environment
    // (never argv — argv is world-visible via ps).
    var u = String(url || "").trim()
    if (u === "") return
    if (u.length > maxInput) { lastError = "URL too long — refused"; return }
    if (!/^https:\/\//i.test(u)) { lastError = "Subscription URL must be https://…"; return }
    runLong([manager, "import", "-"], "import", 240000, "Imported", "Importing…", { OMARCHY_XRAY_SUB_URL: u })
  }

  function subRemove(index) {
    var i = parseInt(index, 10)
    if (!isFinite(i) || i < 0 || i > 63) return
    runLong([manager, "subremove", String(i)], "remove", 120000, "Subscription removed", "Removing…")
  }

  function setMode(newMode) {
    if (newMode !== "proxy" && newMode !== "tun") { lastError = "Bad mode — refused"; return }
    if (newMode === "tun" && !tunInstalled) { tunSetup(true); return }
    runLong([manager, "mode", newMode], "mode switch", 180000, "Mode: " + newMode,
            newMode === "tun" ? "Switching to TUN…" : "Switching to proxy…")
  }

  // One-time privileged setup through polkit (pkexec prompt). On success the
  // TUN unit starts/stops without further prompts.
  function tunSetup(thenSwitch) {
    runLong([manager, "tun-setup"], "TUN setup", 330000, "TUN mode ready",
            "TUN setup — confirm the polkit prompt…", undefined, function(resp) {
      if (resp.ok) {
        tunInstalled = true
        if (thenSwitch) Qt.callLater(function() { setMode("tun") })
      }
    })
  }

  function setRouting(preset) {
    if (preset !== "global" && preset !== "ru-direct") return
    runLong([manager, "routing", preset], "routing", 120000, "Routing: " + preset, "Applying routing…")
  }

  function setAdblock(on) {
    runLong([manager, "adblock", on ? "on" : "off"], "adblock", 120000,
            on ? "Ad blocking on" : "Ad blocking off", "Applying…")
  }

  function openWebUi() {
    Quickshell.execDetached(["xdg-open", Quickshell.env("HOME") + "/.config/omarchy-xray"])
  }

  // Traffic straight from xray's loopback metrics — no python, no extra xray
  // process per poll; speeds are derived here from consecutive samples.
  function pollStats() {
    if (!installed || _stats.running || !coreRunning) {
      if (!coreRunning) traffic = null
      return
    }
    run(_stats, ["/usr/bin/curl", "-s", "--max-time", "2", "--noproxy", "*", metricsUrl], function(resp) {
      _statsDeadline.stop()
      var next = resp.data ? Model.parseMetrics(resp.data, traffic, Date.now()) : null
      traffic = next
    })
    armDeadline(_stats, _statsDeadline, 10000, "stats")
  }

  function persistLastNode(key) {
    if (panelRef && typeof panelRef.persistSetting === "function") panelRef.persistSetting("lastNodeKey", key)
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
    running: root.coreRunning && (root.panelOpen || root.barLabel === "speed")
    triggeredOnStart: true
    onTriggered: root.pollStats()
  }

  Timer {
    id: actionStatusTimer
    interval: 2400
    repeat: false
    onTriggered: root.actionStatus = ""
  }

  Timer {
    id: _actionDeadline
    interval: 30000
    repeat: false
    onTriggered: root.onDeadline(_action, _actionDeadline)
  }

  Timer {
    id: _statsDeadline
    interval: 10000
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
    property string _label: ""
    clearEnvironment: true
    running: false
    command: []
    stdout: StdioCollector { id: actionStdout; waitForEnd: true }
    stderr: StdioCollector { id: actionStderr; waitForEnd: true }
    onExited: function(exitCode) {
      root.finish(_action, String(actionStdout.text || ""), String(actionStderr.text || ""), exitCode)
    }
  }

  Process {
    id: _stats
    property var _done: null
    property string _label: ""
    clearEnvironment: true
    running: false
    command: []
    stdout: StdioCollector { id: statsStdout; waitForEnd: true }
    stderr: StdioCollector { waitForEnd: true }
    onExited: function(exitCode) {
      var done = _stats._done
      _stats._done = null
      var data = exitCode === 0 ? root.extractJson(String(statsStdout.text || "")) : null
      if (done) done({ ok: data !== null, data: data, message: "" })
    }
  }

  Process {
    id: _long
    property var _done: null
    property string _label: ""
    clearEnvironment: true
    running: false
    command: []
    stdout: StdioCollector { id: longStdout; waitForEnd: true }
    stderr: StdioCollector { id: longStderr; waitForEnd: true }
    onExited: function(exitCode) {
      root.finish(_long, String(longStdout.text || ""), String(longStderr.text || ""), exitCode)
    }
  }
}
