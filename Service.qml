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
  readonly property string barLabel: strSetting("barLabel", "icon")

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
  function run(slot, args, done) {
    if (slot.running) return false
    slot._done = done
    slot.command = args
    slot.running = true
    return true
  }

  function finish(slot, stdoutText, exitCode) {
    var done = slot._done
    slot._done = null
    var parsed = null
    try { parsed = JSON.parse(stdoutText) } catch (e) { parsed = null }
    var resp = { ok: parsed !== null && parsed.ok !== false, data: parsed,
                 message: parsed && parsed.error ? parsed.error : "" }
    if (exitCode !== 0 && resp.message === "") resp.message = "omarchy-xray exited with code " + exitCode
    reachable = true
    installed = true
    if (done) done(resp)
    return resp
  }

  function managerFail(message) {
    reachable = false
    installed = false
    lastError = "Xray manager not found — reinstall the widget (./install.sh)"
    if (message !== "") lastError = message
  }

  // --- actions ------------------------------------------------------------

  function refresh() {
    if (!run(_action, ["omarchy-xray", "status"], applyStatus)) return
  }

  function applyStatus(resp) {
    if (!resp.ok || !resp.data || !resp.data.touch) {
      if (resp.message !== "") { reachable = false; lastError = resp.message; installed = false }
      return
    }
    reachable = true
    installed = true
    lastError = ""
    mode = String(resp.data.mode || "proxy")
    subs = resp.data.subs || []
    touch = resp.data.touch
  }

  function connectNode(node) {
    if (!node || !node.key) return
    if (!run(_action, ["omarchy-xray", "select", node.key], function(resp) {
      if (!resp.ok) { lastError = "Select failed: " + (resp.message || "?"); return }
      actionStatus = "Switched to " + node.name
      actionStatusTimer.restart()
      persistLastNode(node.key)
      if (!coreRunning) cmdOn()
      else refresh()
    })) { busyRefused(); return }
  }

  function disconnect() {
    if (!run(_action, ["omarchy-xray", "off"], function(resp) {
      if (resp.ok) { actionStatus = "Disconnected"; actionStatusTimer.restart() }
      else lastError = "Disconnect failed: " + (resp.message || "?")
      refresh()
    })) { busyRefused(); return }
  }

  function cmdOn() {
    if (!run(_action, ["omarchy-xray", "on"], function(resp) {
      if (!resp.ok) lastError = "Start failed: " + (resp.message || "?")
      else { actionStatus = "Connected"; actionStatusTimer.restart() }
      refresh()
    })) { busyRefused(); return }
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
    if (!run(_long, ["omarchy-xray", "test"], function(resp) {
      if (resp.ok) { actionStatus = "Latency test done"; actionStatusTimer.restart() }
      else { actionStatus = ""; lastError = "Test failed: " + (resp.message || "?") }
      refresh()
    })) { busyRefused(); return }
    actionStatus = "Testing all nodes…"
    testWatchdog.restart()
  }

  function updateSubscriptions() {
    if (!run(_long, ["omarchy-xray", "update"], function(resp) {
      if (resp.ok) { actionStatus = "Subscriptions updated"; actionStatusTimer.restart() }
      else { actionStatus = ""; lastError = "Update failed: " + (resp.message || "?") }
      refresh()
    })) { busyRefused(); return }
    actionStatus = "Updating subscription…"
    testWatchdog.restart()
  }

  function importUrl(url) {
    var u = String(url || "").trim()
    if (u === "") return
    if (!run(_long, ["omarchy-xray", "import", u], function(resp) {
      if (resp.ok) { actionStatus = "Imported"; actionStatusTimer.restart() }
      else { actionStatus = ""; lastError = "Import failed: " + (resp.message || "?") }
      refresh()
    })) { busyRefused(); return }
    actionStatus = "Importing…"
    testWatchdog.restart()
  }

  function openWebUi() {
    Quickshell.execDetached(["xdg-open", Quickshell.env("HOME") + "/.config/omarchy-xray"])
  }

  function pollStats() {
    if (!installed || _stats.running) return
    run(_stats, ["omarchy-xray", "stats"], function(resp) {
      if (resp.ok && resp.data && resp.data.running !== false) traffic = resp.data
      else traffic = null
    })
  }

  function setMode(mode) {
    if (!installed || _long.running) return
    actionStatus = mode === "tun" ? "Switching to TUN — confirm the polkit prompt…" : "Switching to proxy…"
    run(_long, ["omarchy-xray", "mode", mode], function(resp) {
      if (resp.ok) { actionStatus = "Mode: " + mode; actionStatusTimer.restart() }
      else { actionStatus = ""; lastError = "Mode switch failed: " + (resp.message || "?") }
      refresh()
    })
    testWatchdog.restart()
  }

  function subRemove(url) {
    if (!installed || _long.running) return
    run(_long, ["omarchy-xray", "subremove", url], function(resp) {
      if (!resp.ok) lastError = "Remove failed: " + (resp.message || "?")
      refresh()
    })
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

  Timer {
    // test/update can legitimately run ~a minute; reap hung runs
    id: testWatchdog
    interval: 150000
    repeat: false
    onTriggered: if (_long.running) _long.running = false
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
