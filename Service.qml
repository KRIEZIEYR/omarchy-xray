import QtQuick
import Quickshell
import Quickshell.Io
import "model/Xray.js" as Model

/*
 * Backend: the omarchy-xray manager in this plugin's bin/ folder. xray runs
 * as a systemd user unit in both modes; TUN mode adds tun2socks (user unit)
 * and a root oneshot that only creates the device (one-time `tun-setup`).
 * Every call is a plain subprocess with JSON on stdout; traffic comes
 * straight from xray's loopback metrics endpoint.
 */
Item {
  id: root

  property var settings: ({})
  property var panelRef: null
  property bool panelOpen: false

  // --- observable state ---------------------------------------------------
  property bool reachable: false        // manager answered
  property bool installed: true         // manager found
  property bool _quietNext: false
  property bool dropped: false          // a unit crashed while wanted; it is restarting
  property bool blocked: false          // ...and in TUN the kill switch blocks traffic meanwhile
  property int _restarts: -1
  property string lastError: ""         // last failed user action; cleared by the next one or a healthy poll
  property double _errorAt: 0
  onLastErrorChanged: _errorAt = Date.now()
  property string serviceError: ""      // from status: manager/core/unit health
  readonly property string errorText: lastError !== "" ? lastError : serviceError
  property string actionStatus: ""
  property var touch: null              // {running, groups, nodes, connectedKeys}
  property var traffic: null            // {upTotal, downTotal, upSpeed, downSpeed, autoPick}
  property string mode: "proxy"
  property string routing: "global"
  property var regions: []              // [{code, name, flag}] from the manager
  readonly property var region: {
    for (var i = 0; i < regions.length; i++)
      if (routing === regions[i].code + "-direct") return regions[i]
    return null
  }
  property bool adblock: false
  property string dns: "cloudflare"
  property bool geo: false
  property bool tunInstalled: false
  property var subs: []
  property string skippedText: ""
  property var autoMembers: []
  property string metricsUrl: "http://127.0.0.1:15491/debug/vars"
  property string _statusRaw: ""
  property real _lastAutoUpdate: 0
  property string _busyText: ""
  property real longStartedMs: 0         // a flash over a long job falls back to this

  readonly property int connectedCount: touch !== null ? Object.keys(touch.connectedKeys || {}).length : 0
  readonly property bool connected: connectedCount > 0
  readonly property bool coreRunning: touch !== null && touch.running === true
  readonly property string autoPickName: traffic ? Model.autoPickName(autoMembers, touch ? touch.nodes : [], traffic.autoPick) : ""

  // "connecting" | "switching" | "disconnecting" while a connection change runs.
  property string pending: ""

  // The node the connect switch / `c` will use (shown while disconnected).
  readonly property var connectTarget: touch ? Model.pickConnectTarget(touch, String(setting("lastNodeKey", ""))) : null

  readonly property var _heroInput: ({
    pending: pending,
    target: connectTarget ? connectTarget.name : "",
    blocked: blocked,
    dropped: dropped,
    hasSubs: subs.length > 0,
    unreachable: !reachable,
    touch: touch,
    mode: mode,
    autoPick: autoPickName
  })
  readonly property string heroSummary: Model.heroLine(_heroInput)
  readonly property string heroTitle: Model.heroTitle(_heroInput)
  readonly property string heroState: Model.heroState(_heroInput)

  readonly property int refreshIntervalSec: intSetting("refreshIntervalSec", 20, 10, 600)

  // Hardening bounds: stdout cap (bytes), node cap for rendering, input caps.
  readonly property int outCap: 524288
  readonly property int maxNodes: 1000
  readonly property int maxInput: 2048
  readonly property int maxPaste: 120 * 1024   // links or Xray JSON (the manager's MAX_PASTE)
  // Shipped next to this file: `omarchy plugin add` clones the repo as is.
  readonly property string manager: decodeURIComponent(String(Qt.resolvedUrl("bin/omarchy-xray")).replace(/^file:\/\//, ""))

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

  readonly property bool busy: _action.running || _long.running
  readonly property bool testing: _long.running && _long._label === "latency test"
  // The connect toggle only waits for short commands: a latency test (up to
  // 11 min) must not swallow disconnect. Other long jobs rewrite state and
  // would race a node switch, so they still hold it.
  // A subscription that errored or ran out keeps a badge on the bar.
  readonly property bool subsTrouble: {
    var now = Date.now() / 1000
    for (var i = 0; i < subs.length; i++) {
      var s = subs[i] || {}
      var e = Number(s.info && s.info.expire) || 0
      if (s.error || (e > 0 && e < now)) return true
    }
    return false
  }
  readonly property bool toggleBusy: _action.running || (_long.running && !testing)

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
      lastError = "That text is too long (2048 characters at most)"
      return false
    }
    var quiet = _quietNext
    _quietNext = false
    var env = {}
    for (var k in baseEnv) env[k] = null
    if (extraEnv) for (var x in extraEnv) env[x] = extraEnv[x]
    // a background job (auto-update) must not wipe an error the user has not seen
    if ((slot === _action || slot === _long) && !quiet) lastError = ""
    slot._terminating = false
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

  // Deadline: SIGTERM first so the manager can stop its own children (latency
  // probes run in their own sessions and would outlive a SIGKILL); SIGKILL
  // only if it is still there 3 s later.
  function onDeadline(slot, timer) {
    timer.stop()
    if (!slot.running) return
    if (slot._terminating) { try { slot.signal(9) } catch (e) {} ; return }
    slot._terminating = true
    slot._done = null
    try { slot.signal(15) } catch (e1) {}
    timer.interval = 3000
    timer.restart()
    try { slot.environment = ({}) } catch (e2) {}
    var msg = scrub(opName(slot._label) + " took too long and was stopped. Try again")
    if (slot === _action || slot === _long) lastError = msg
    else serviceError = msg
    if (slot === _action) pending = ""
    actionStatus = ""
    refresh()
  }

  function managerFail(message) {
    reachable = false
    installed = false
    serviceError = message !== "" ? message : "Xray manager did not start (needs /usr/bin/python3) — reinstall the plugin if python is present"
  }

  function flash(text) {
    actionStatus = text
    actionStatusTimer.interval = Math.max(2400, String(text).length * 70)   // long enough to read
    actionStatusTimer.restart()
  }

  // What a running command is doing, for "wait" and "took too long" copy.
  function opName(label) {
    var names = { "select": "Switching nodes", "start": "Connecting", "disconnect": "Disconnecting",
                  "latency test": "The latency test", "update": "The subscription update",
                  "import": "Adding", "remove": "Removing the subscription",
                  "mode switch": "Switching mode", "TUN setup": "TUN setup", "routing": "Applying routing",
                  "adblock": "Applying ad blocking", "dns": "Changing DNS", "status": "Reading status", "stats": "Reading traffic" }
    return names[label] || "The last command"
  }

  function busyRefused() {
    if (testing) { flash("A latency test is running: stop it (Ctrl+T) to change settings"); return }
    var slot = _long.running ? _long : _action
    flash(opName(slot._label) + " is still running. Try again in a moment")
  }

  // --- status -------------------------------------------------------------

  // Status polls get their own slot: sharing _action made `busy` blink every
  // poll and dropped clicks that landed on one. A refresh asked for mid-poll
  // runs right after it, so the UI never settles on pre-action state.
  property bool _refreshAgain: false

  function refresh() {
    if (_status.running) { _refreshAgain = true; return }
    if (!run(_status, [manager, "status"], applyStatusAndStop)) return
    armDeadline(_status, _statusDeadline, 30000, "status")
  }

  function applyStatusAndStop(resp) {
    _statusDeadline.stop()
    applyStatus(resp)
    if (_refreshAgain) { _refreshAgain = false; refresh() }
  }

  // Once per shell start (that is, per login): connect if asked to, then a
  // latency test shortly after, and again every 30 minutes.
  property bool _started: false
  function _onStart() {
    if (setting("autoConnect", false) === true && !connected && !blocked && !dropped && pending === "")
      toggleConnection(String(setting("lastNodeKey", "")))
    autoTestDelay.start()
  }
  function autoTest() {
    if (testing || busy || pending !== "" || !touch || !touch.nodes || touch.nodes.length < 2) return
    testNodes(touch.nodes)
  }
  Timer { id: autoTestDelay; interval: 20000; onTriggered: autoTest() }
  Timer { interval: 30 * 60 * 1000; repeat: true; running: reachable; onTriggered: autoTest() }

  function applyStatus(resp) {
    if (!resp.ok || !resp.data || !resp.data.nodes) {
      if (resp.message !== "") serviceError = scrub(resp.message)
      return
    }
    var d = resp.data
    reachable = true
    if (!_started) { _started = true; Qt.callLater(_onStart) }
    installed = true
    mode = String(d.mode || "proxy")
    routing = String(d.routing || "global")
    if (regions.length === 0 && d.regions && d.regions.slice) regions = d.regions.slice(0, 32)   // static list
    adblock = d.adblock === true
    if (typeof d.dns === "string") dns = d.dns
    geo = d.geo === true
    tunInstalled = d.tunInstalled === true
    skippedText = Model.skippedLabel(d.skipped)
    autoMembers = d.autoMembers || []
    if (d.metricsUrl && /^http:\/\/127\.0\.0\.1:\d+\/debug\/vars$/.test(d.metricsUrl)) metricsUrl = d.metricsUrl
    // An action's error stays readable for a while, then a healthy poll
    // gives the line back to live traffic.
    if (lastError !== "" && Date.now() - _errorAt > 15000) lastError = ""
    serviceError = d.blocked === true ? "Kill switch: traffic is blocked while the VPN reconnects"
                 : d.dropped === true ? "VPN dropped: reconnecting…"
                 : d.lastError ? "Xray stopped with an error: " + scrub(d.lastError) : (d.xray === false ? "xray core not found — install it (omarchy pkg aur add xray)" : "")
    var rawSubs = d.subs || []
    subs = rawSubs.slice ? rawSubs.slice(0, 64) : []
    // Rebuild the node model only when something changed: reassigning `touch`
    // recreates every delegate, which the 2 s open-panel poll made visible.
    var raw = JSON.stringify([d.nodes, d.subs, d.connectedKey, d.running])
    if (raw !== _statusRaw || touch === null) {
      _statusRaw = raw
      touch = Model.groupsFromStatus(d, maxNodes, Math.floor(Date.now() / 1000))
    }
    if (d.updateDue === true && !busy && !panelOpen && Date.now() - _lastAutoUpdate > 600000) {
      _lastAutoUpdate = Date.now()
      _quietNext = true
      updateSubscriptions()
    }
    if (testing && d.testProgress && d.testProgress.total > 0)
      actionStatus = "Testing " + d.testProgress.done + "/" + d.testProgress.total + "…"

    // Drops come from the manager's unit states (a crash while enabled), so
    // an off, a mode switch or a node switch never raises one, and a busy job
    // does not hide one. The restart counter catches a crash that recovered
    // between two polls.
    var nowDropped = d.dropped === true
    blocked = d.blocked === true
    if (nowDropped && !dropped)
      Quickshell.execDetached(["notify-send", "-u", "critical", "-a", "Xray", "VPN dropped",
        blocked ? "Traffic is blocked until it reconnects or you turn it off" : "Reconnecting…"])
    else if (!nowDropped && dropped && d.running === true)
      Quickshell.execDetached(["notify-send", "-u", "low", "-a", "Xray", "VPN reconnected"])
    else if (!nowDropped && _restarts >= 0 && (d.restarts || 0) > _restarts)
      Quickshell.execDetached(["notify-send", "-a", "Xray", "VPN recovered from a crash",
                               "It was down for a few seconds and reconnected on its own"])
    dropped = nowDropped
    _restarts = typeof d.restarts === "number" ? d.restarts : -1
  }

  // --- actions ------------------------------------------------------------

  // Picking a node in the list: switches while the tunnel runs, otherwise
  // only remembers it for the switch (no surprise connection).
  function selectNode(node) {
    if (!node || !node.key) return
    if (coreRunning || connected || pending !== "") { connectNode(node); return }
    persistLastNode(node.key)          // the lit radio and the hero say it
  }

  function connectNode(node) {
    if (!node || !node.key) return
    if (_long.running && !testing) { busyRefused(); return }   // an update or mode switch owns the state
    if (String(node.key).length > 64) { lastError = "That node is no longer in the list — reopen the panel"; return }
    var wasRunning = coreRunning
    if (!run(_action, [manager, "select", node.key], function(resp) {
      _actionDeadline.stop()
      if (!resp.ok) {
        pending = ""; actionStatus = ""
        lastError = "Couldn't switch to " + scrub(node.name) + ": " + (resp.message || "no details"); refresh(); return
      }
      persistLastNode(node.key)
      if (!coreRunning) { cmdOn(true); return }
      pending = ""
      flash("Switched to " + scrub(node.name))
      refresh()
    })) { busyRefused(); return }
    pending = wasRunning ? "switching" : "connecting"
    actionStatusTimer.stop()
    actionStatus = (wasRunning ? "Switching to " : "Connecting to ") + scrub(node.name) + "…"
    armDeadline(_action, _actionDeadline, 60000, "select")
  }

  function disconnect() {
    if (!run(_action, [manager, "off"], function(resp) {
      _actionDeadline.stop()
      pending = ""
      if (resp.ok) actionStatus = ""        // the hero says Not protected
      else { actionStatus = ""; lastError = "Couldn't disconnect: " + (resp.message || "no details") }
      traffic = null
      refresh()
    })) { busyRefused(); return }
    pending = "disconnecting"
    actionStatusTimer.stop()
    actionStatus = "Disconnecting…"
    armDeadline(_action, _actionDeadline, 60000, "disconnect")
  }

  // chained: called from connectNode's callback, which already shows the status
  function cmdOn(chained) {
    if (!run(_action, [manager, "on"], function(resp) {
      _actionDeadline.stop()
      pending = ""
      if (!resp.ok) { actionStatus = ""; lastError = "Couldn't connect: " + (resp.message || "no details") }
      // proxy mode reaches apps through their proxy settings: ones already
      // running may not re-read them; TUN says nothing, the hero shows it
      else if (mode !== "tun") flash("Apps already open may need a restart")
      else actionStatus = ""
      refresh()
    })) { busyRefused(); return }
    if (!chained) {
      pending = "connecting"
      actionStatusTimer.stop()
      actionStatus = "Connecting…"
    }
    armDeadline(_action, _actionDeadline, 120000, "start")
  }

  // Every way to connect or disconnect (switch, Enter, bar right-click, IPC)
  // lands here or in connectNode. A dropped or blocked tunnel counts as on:
  // toggling it turns it off, which also lifts the kill switch.
  function toggleConnection(lastKey) {
    if (connected || blocked || dropped) { disconnect(); return }
    var target = Model.pickConnectTarget(touch || {}, lastKey)
    if (target === null) { lastError = subs.length > 0 ? "No usable nodes: every link was skipped (see below)"
                                                    : "No nodes yet: add a subscription or a server link first"; return }
    connectNode(target)
  }

  function runLong(args, label, deadlineMs, okText, busyText, extraEnv, after) {
    if (!installed && label !== "import") return
    if (!run(_long, args, function(resp) {
      _longDeadline.stop()
      var what = label.charAt(0).toUpperCase() + label.substring(1)
      var msg = resp.message || "no details"
      if (resp.ok) flash(typeof okText === "function" ? okText(resp.data || {}) : okText)
      else { actionStatus = ""; lastError = msg.indexOf(what) === 0 ? msg : what + " failed: " + msg }
      if (after) after(resp)
      refresh()
    }, extraEnv)) { busyRefused(); return }
    actionStatusTimer.stop()
    longStartedMs = Date.now()
    _busyText = busyText
    actionStatus = busyText
    armDeadline(_long, _longDeadline, deadlineMs, label)
  }

  // Tests what the list shows: one row, the filtered subset, or everything
  // (Auto or an unfiltered list). A second call while testing stops it.
  function testNodes(nodes) {
    if (testing) { stopTest(); return }
    var list = nodes || []
    var keys = [], total = 0, first = ""
    for (var i = 0; i < list.length && keys.length < 200; i++) {
      if (!list[i].key || list[i].key === "auto") continue
      if (first === "") first = list[i].name
      keys.push(String(list[i].key))
    }
    var all = touch ? touch.nodes : []
    for (var j = 0; j < all.length; j++) if (all[j].key !== "auto") total++
    var subset = keys.length > 0 && keys.length < total
    var label = !subset ? "Testing " + total + " nodes…"
              : keys.length === 1 ? "Testing " + scrub(first) + "…"
              : "Testing " + keys.length + " nodes…"
    runLong([manager, "test"].concat(subset ? keys : []), "latency test", 660000,
            "",                                // results show in the list; no status line
            label, undefined, function(resp) {
      // no status line either way: the Test button counts the failures
      if (!resp.ok) lastError = ""
    })
  }

  function stopTest() {
    if (!testing) return
    actionStatus = "Stopping test…"
    try { _long.signal(15) } catch (e) {}
  }

  function testNode(node) { if (node) testNodes([node]) }

  function updateSubscriptions() {
    runLong([manager, "update"], "update", 240000,
            "", "Updating subscriptions…")        // the button and the list show it
  }

  function updateSub(index) {
    var i = parseInt(index, 10)
    if (!isFinite(i) || i < 0 || i > 63) return
    runLong([manager, "update", String(i)], "update", 180000,
            "", "Updating subscription…")
  }

  // Import progress and failures, shown next to the URL field itself (the
  // panel may be scrolled to the subscriptions when they happen).
  property string importNote: ""
  readonly property bool importing: _long.running && _long._label === "import"
  readonly property bool updating: _long.running && _long._label === "update"

  function importUrl(url, onDone) {
    // A subscription URL, share links or Xray JSON: all secrets, bounded and
    // passed via the environment (never argv — argv is world-visible via ps).
    // The manager tells them apart and explains what it refuses.
    var u = String(url || "").trim()
    if (u === "") return
    var sub = /^https?:\/\/\S+$/i.test(u)
    var bad = u.length > (sub ? maxInput : maxPaste) ? "That is too long to add" : ""
    if (bad !== "") { lastError = bad; importNote = bad; return }
    var busyText = sub ? "Downloading the subscription…" : "Checking the servers…"
    runLong([manager, "import", "-"], "import", 240000,
            function(d) {
              return d.manual ? "Added " + d.manual + (d.manual === 1 ? " server" : " servers") + " to Manual"
                              : "Subscription added: " + (d.nodes || 0) + " nodes available"
            },
            busyText, { OMARCHY_XRAY_SUB_URL: u },
            function(resp) {
              importNote = resp.ok ? "" : lastError
              if (onDone) onDone(resp.ok)
            })
    if (importing) importNote = busyText
  }

  function subRemove(index) {
    var i = parseInt(index, 10)
    if (!isFinite(i) || i < 0 || i > 63) return
    runLong([manager, "subremove", String(i)], "remove", 120000, "Subscription removed", "Removing the subscription…")
  }

  function setMode(newMode) {
    if (newMode !== "proxy" && newMode !== "tun") { lastError = "Unknown mode: pick proxy or TUN"; return }
    if (newMode === "tun" && !tunInstalled) { tunSetup(true); return }
    runLong([manager, "mode", newMode], "mode switch", 180000, function(d) {
              var name = newMode === "tun" ? "TUN" : "proxy"
              return d.running ? "Switched to " + name + " mode" : name.charAt(0).toUpperCase() + name.substring(1) + " mode set. Connect to start"
            },
            newMode === "tun" ? "Switching to TUN…" : "Switching to proxy…")
  }

  // One-time privileged setup through polkit (pkexec prompt). On success the
  // TUN unit starts/stops without further prompts.
  function tunSetup(thenSwitch) {
    runLong([manager, "tun-setup"], "TUN setup", 330000, "TUN mode ready",
            "Setting up TUN: enter your password in the system prompt…", undefined, function(resp) {
      if (resp.ok) {
        tunInstalled = true
        if (thenSwitch) Qt.callLater(function() { setMode("tun") })
      }
    })
  }

  function setRouting(preset) {
    if (preset !== "global" && !/^[a-z]{2}-direct$/.test(preset)) return
    runLong([manager, "routing", preset], "routing", 120000,
            preset === "global" ? "Everything goes through the VPN" : regionName(preset) + " sites now bypass the VPN",
            "Applying routing…")
  }

  function regionName(preset) {
    for (var i = 0; i < regions.length; i++)
      if (preset === regions[i].code + "-direct") return regions[i].name
    return preset.substring(0, 2).toUpperCase()
  }

  function setDns(name) {
    runLong([manager, "dns", name], "dns", 120000, "DNS: " + name, "Changing DNS…")
  }

  function setAdblock(on) {
    runLong([manager, "adblock", on ? "on" : "off"], "adblock", 120000,
            on ? "Ad blocking on" : "Ad blocking off", on ? "Turning ad blocking on…" : "Turning ad blocking off…")
  }

  // The journal of both user units, in Omarchy's floating terminal.
  function openLogs() {
    Quickshell.execDetached(["omarchy-launch-floating-terminal-with-presentation",
      "journalctl --user -u omarchy-xray.service -u omarchy-xray-tun2socks.service -n 100 -f"])
  }

  function openDoctor() {
    var q = "'" + manager.replace(/'/g, "'\\''") + "'"
    Quickshell.execDetached(["omarchy-launch-floating-terminal-with-presentation",
      q + " doctor | python3 -m json.tool; read -r -p 'Enter closes'"])
  }

  function openFolder() {
    Quickshell.execDetached(["xdg-open", Quickshell.env("HOME") + "/.config/omarchy-xray"])
  }

  // Traffic straight from xray's loopback metrics, fetched by the QML engine
  // itself (a curl process every 2 s added up to 30 spawns a minute while
  // connected); speeds are derived here from consecutive samples.
  property var _statsXhr: null

  function pollStats() {
    if (!installed || !coreRunning) {
      if (!coreRunning) traffic = null
      return
    }
    if (_statsXhr !== null) return
    var xhr = new XMLHttpRequest()
    _statsXhr = xhr
    xhr.onreadystatechange = function() {
      if (xhr.readyState !== XMLHttpRequest.DONE || _statsXhr !== xhr) return
      _statsXhr = null
      _statsDeadline.stop()
      var data = null
      if (xhr.status === 200 && xhr.responseText.length <= outCap) {
        try { data = JSON.parse(xhr.responseText) } catch (e) {}
      }
      traffic = data ? Model.parseMetrics(data, traffic, Date.now()) : null
    }
    xhr.open("GET", metricsUrl)
    xhr.send()
    _statsDeadline.restart()
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

  // Open-panel poll only catches outside changes (every action refreshes on
  // completion, traffic has its own 2 s XHR), so each Python spawn can be rarer.
  Timer {
    interval: 4000
    repeat: true
    running: root.panelOpen
    onTriggered: root.refresh()
  }

  Timer {
    id: statsTimer
    interval: 2000
    repeat: true
    running: root.coreRunning && root.panelOpen
    triggeredOnStart: true
    onTriggered: root.pollStats()
  }

  Timer {
    id: actionStatusTimer
    interval: 2400
    repeat: false
    onTriggered: root.actionStatus = _long.running ? root._busyText : ""
  }

  Timer {
    id: _actionDeadline
    interval: 30000
    repeat: false
    onTriggered: root.onDeadline(_action, _actionDeadline)
  }

  Timer {
    id: _statusDeadline
    interval: 30000
    repeat: false
    onTriggered: root.onDeadline(_status, _statusDeadline)
  }

  Timer {
    id: _statsDeadline
    interval: 10000
    repeat: false
    onTriggered: if (root._statsXhr !== null) { root._statsXhr.abort(); root._statsXhr = null }
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
    property bool _terminating: false
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
    id: _status
    property var _done: null
    property string _label: ""
    property bool _terminating: false
    clearEnvironment: true
    running: false
    command: []
    stdout: StdioCollector { id: statusStdout; waitForEnd: true }
    stderr: StdioCollector { id: statusStderr; waitForEnd: true }
    onExited: function(exitCode) {
      root.finish(_status, String(statusStdout.text || ""), String(statusStderr.text || ""), exitCode)
    }
  }

  Process {
    id: _long
    property var _done: null
    property string _label: ""
    property bool _terminating: false
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
