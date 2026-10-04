import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "model/Xray.js" as Model

Panel {
  id: root
  moduleName: "krieziey.omarchy-xray"
  ipcTarget: "krieziey.omarchy-xray"
  manageIpc: false

  // --- cursor / keyboard state -------------------------------------------
  property bool cursorActive: false
  // A key was pressed since the panel opened. Hover also moves the cursor
  // (cursorActive), so the key legend must not follow it: it would pop in
  // and out as the pointer crosses rows and buttons, resizing the panel.
  property bool keysUsed: false
  property bool legendHidden: false      // `?` — remembered while the shell runs
  property bool keyboardUser: false      // keys were used in an earlier open: no layout jump
  onKeysUsedChanged: if (keysUsed) keyboardUser = true
  readonly property bool filterFocused: nodeList.headerItem !== null && nodeList.headerItem.search.activeFocus
  readonly property bool urlFocused: nodeList.footerItem !== null && nodeList.footerItem.subUrl.activeFocus
  property int nodeIndex: 0
  property string filterQuery: ""
  property bool regionsOpen: false
  property int regionHover: -1
  // No subscription yet: hide what cannot be used and bring the URL field up.
  readonly property bool firstRun: xray.reachable && xray.touch !== null && xray.subs.length === 0
  property bool subsOpen: false
  readonly property bool subsShown: subsOpen || xray.subs.length === 0
  readonly property real settingLabelWidth: Style.space(64)
  readonly property string lastRegion: settings ? String(settings.lastRegion || "") : ""
  // DIRECT remembers its country, so ALL <-> DIRECT is one click.
  readonly property var routeRegion: {
    if (xray.region) return xray.region
    for (var i = 0; i < xray.regions.length; i++)
      if (xray.regions[i].code === lastRegion) return xray.regions[i]
    return null
  }

  function pickRegion(code) {
    if (xray.busy) { xray.busyRefused(); return }
    regionsOpen = false
    persistSetting("lastRegion", code)
    if (xray.routing !== code + "-direct") xray.setRouting(code + "-direct")
  }

  function chooseMode(m) {
    if (xray.busy) { xray.busyRefused(); return }
    if (m !== xray.mode) xray.setMode(m)
  }

  function chooseRoute(v) {
    if (xray.busy) { xray.busyRefused(); return }
    if (v === "global") { if (xray.routing !== "global") xray.setRouting("global") }
    else if (v === "blocked") { if (xray.routing !== "ru-blocked") xray.setRouting("ru-blocked") }
    else if (!xray.region) {
      if (routeRegion) xray.setRouting(routeRegion.code + "-direct")
      else regionsOpen = true
    }
  }

  // One keyboard cursor walks the whole panel, as in Network: settings rows
  // above the nodes (nodeIndex < 0, -1 = the last one), the node rows
  // (0..n-1), then the subscriptions (header, then one row each).
  // h/l pick a chip inside a row, Enter applies it.
  // Mode, route and adblock are set-and-forget: one summary row until opened,
  // so the nodes start right under the switch.
  property bool settingsOpen: false      // remembered while the shell runs
  readonly property var settingRows: !xray.reachable || firstRun ? []
      // the same order as on the page
      : ["hero", "settings"].concat(settingsOpen ? ["mode", "route"].concat(regionsOpen ? ["regions"] : [],
          ["login", "dns", "dnsown", "ads", "fragment"], xray.fragment ? ["fragopts"] : [],
          ["mux"], xray.mux ? ["muxc"] : [], ["auto", "chain", "subupd", "failover", "lan", "links", "log", "ua", "geo", "geodays", "backup", "check", "ruleadd"], xray.rules.map(function(r, i) { return "rule" + i })) : [])
  readonly property string settingsSummary: (xray.mode === "tun" ? "TUN" : "PROXY")
      + " · " + (xray.routing === "ru-blocked" ? "RU BLOCKED" : xray.region ? xray.region.code.toUpperCase() + " DIRECT" : "ALL")
      + (xray.adblock ? " · ADBLOCK" : "")
      + (xray.fragment ? " · FRAG" : "")
      + (xray.rules.length ? " · " + xray.rules.length + " RULES" : "")
      + " · " + (xray.dns === "custom" ? "OWN DNS" : dnsOptions[dnsIndex()].label)
  function toggleSettings() {
    var onRow = cursorRow === "settings"
    if (settingsOpen) regionsOpen = false
    settingsOpen = !settingsOpen
    if (onRow) nodeIndex = settingRows.indexOf("settings") - settingRows.length
  }
  // Settings are a page of their own: while open, nodes and subscriptions step aside.
  readonly property int footerRows: xray.reachable && !settingsOpen ? 1 + (subsShown ? xray.subs.length : 0) : 0
  readonly property int cursorRule: cursorRow.indexOf("rule") === 0 && cursorRow !== "ruleadd" ? parseInt(cursorRow.substring(4), 10) : -1
  // Target for the next rule: picked with the chips (h/l) before typing.
  property string ruleTarget: "direct"
  readonly property var ruleTargets: [
    { value: "direct", label: "DIRECT", tooltip: "Goes around the VPN" },
    { value: "proxy", label: "VPN", tooltip: "Always through the VPN, also under a DIRECT country" },
    { value: "block", label: "BLOCK", tooltip: "Never loads" }
  ]
  function ruleTargetLabel(v) {
    for (var i = 0; i < ruleTargets.length; i++) if (ruleTargets[i].value === v) return ruleTargets[i].label
    return v
  }
  function addRule(text) {
    if (xray.busy) { xray.busyRefused(); return false }
    var v = String(text || "").trim()
    if (v === "") return false
    xray.addRule(ruleTarget, v)
    return true
  }
  function removeRule(i) {
    if (xray.busy) { xray.busyRefused(); return }
    xray.removeRule(i)
  }
  // Enter in any of the three fields applies all three.
  function applyFragmentOpts() {
    if (xray.busy) { xray.busyRefused(); return }
    var h = nodeList.headerItem
    if (h) xray.setFragment(true, [h.fragPackets.text, h.fragLength.text, h.fragInterval.text])
  }
  // On/off pills: several switches share one row; each pill is lit while on.
  readonly property var trafficPills: [
    { key: "ads", label: "ADBLOCK", on: xray.adblock, usable: xray.geo || xray.adblock,
      tooltip: xray.geo ? "Blocks known ad and tracker domains" : "Needs v2ray-geoip and v2ray-domain-list-community" },
    { key: "fragment", label: "FRAGMENT", on: xray.fragment, usable: true,
      tooltip: "Splits the TLS handshake against DPI · not REALITY" },
    { key: "mux", label: "MUX", on: xray.mux, usable: true,
      tooltip: "Fewer handshakes · not Vision, XHTTP, Hysteria2" }
  ]
  readonly property var switchPills: [
    { key: "login", label: "LOGIN", on: autoConnect, usable: true, tooltip: "Connect when you log in" },
    { key: "lan", label: "LAN", on: xray.lan, usable: true, tooltip: "Your network can use this VPN, with a password" }
  ]
  function flipPill(key) {
    if (key === "login") toggleAutoConnect()
    else if (key === "ads") toggleAdblock()
    else if (key === "fragment") toggleFragment()
    else if (key === "mux") guarded(function() { xray.setOption("mux", xray.mux ? "off" : "on", xray.mux ? "Mux off" : "Mux on") })
    else if (key === "lan") guarded(function() { xray.setOption("lan", xray.lan ? "off" : "on", xray.lan ? "Local network access off" : "Local network access on") })
  }
  readonly property var autoOptions: [
    { value: "all", label: "ALL", tooltip: "Auto picks among the best 32 nodes" },
    { value: "fav", label: "★ ONLY", tooltip: "Auto picks only among starred nodes (all, if none is starred)" }
  ]
  readonly property var logOptions: [
    { value: "error", label: "ERROR", tooltip: "Only errors in the journal" },
    { value: "warning", label: "WARN", tooltip: "Errors and warnings (default)" },
    { value: "info", label: "INFO", tooltip: "Connections too" },
    { value: "debug", label: "DEBUG", tooltip: "Everything: for a bug report, then back" }
  ]
  readonly property var subUpdateOptions: [
    { value: "auto", label: "AUTO", tooltip: "As often as the provider asks, else daily" },
    { value: "6", label: "6H", tooltip: "Every 6 hours" },
    { value: "24", label: "24H", tooltip: "Once a day" },
    { value: "off", label: "OFF", tooltip: "Only when you press Update" }
  ]
  readonly property string subUpdateValue: xray.subUpdate === 0 ? "off" : xray.subUpdate > 0 ? String(xray.subUpdate) : "auto"
  readonly property var geoOptions: [
    { value: "update", label: "UPDATE", tooltip: "Fresh geoip/geosite lists (Loyalsoldier), then weekly by themselves" }
  ]
  // Subscription User-Agents: some panels send a different format (or
  // more nodes) to the client they recognise.
  readonly property var uaOptions: [
    { value: "", label: "Default" },
    { value: "v2rayN/7.13.8", label: "v2rayN" },
    { value: "v2rayNG/1.10.16", label: "v2rayNG" },
    { value: "Happ/2.0.0", label: "Happ" },
    { value: "Streisand/1.6.53", label: "Streisand" },
    { value: "HiddifyNext/2.5.7", label: "Hiddify" },
    { value: "clash-verge/v2.3.1", label: "Clash Verge" },
    { value: "sing-box 1.12.0", label: "sing-box" }
  ]
  readonly property var geoDaysOptions: [
    { value: "1", label: "1D", tooltip: "Every day" },
    { value: "7", label: "7D", tooltip: "Every week (default)" },
    { value: "30", label: "30D", tooltip: "Every month" },
    { value: "0", label: "OFF", tooltip: "Only when you press Update" }
  ]
  readonly property var backupOptions: [
    { value: "copy", label: "COPY", tooltip: "Settings into the clipboard: no subscriptions, no passwords" },
    { value: "paste", label: "PASTE", tooltip: "Settings from the clipboard (an earlier COPY)" }
  ]
  function optIndex(opts, v) { return Math.max(0, opts.findIndex(function(o) { return o.value === v })) }
  function guarded(fn) { if (xray.busy) { xray.busyRefused(); return } fn() }
  function focusField(name) {
    var f = nodeList.headerItem ? nodeList.headerItem[name] : null
    if (f) f.forceActiveFocus()
  }
  readonly property bool sortByLatency: settings ? settings.sortByLatency === true : false
  function cursorNodeOrNull() { return cursorRow === "node" ? selectedNode() : null }

  function toggleFragment() {
    if (xray.busy) { xray.busyRefused(); return }
    xray.setFragment(!xray.fragment)
  }
  property int chipIndex: 0
  readonly property string cursorRow: !cursorActive ? ""
      : nodeIndex < 0 ? (settingRows[settingRows.length + nodeIndex] || "")
      : nodeIndex < visibleNodes.length ? "node"
      // a filter that matches nothing leaves the cursor nowhere: Enter must
      // not fall through to the Config button below the list
      : visibleNodes.length === 0 && filterQuery !== "" ? ""
      : nodeIndex === visibleNodes.length ? "subs" : "sub"
  // The keyboard cursor is drawn, not focused (focus stays on the key
  // catcher), so a screen reader is told where it went.
  readonly property string cursorLabel: {
    var r = cursorRow, c = chipIndex
    if (r === "node") { var n = selectedNode(); return n ? n.name + (n.connected ? ", connected" : "") : "" }
    if (r === "hero") return "VPN switch, " + (xray.blocked ? "kill switch holding" : tunnelUp ? "on" : "off")
    if (r === "settings") return "Settings, " + settingsSummary
    if (r === "mode") return "Mode " + (c === 1 ? "TUN" : "proxy")
    if (r === "route") return c === 2 ? "Change the direct country" : "Route " + ["all", "direct", "", "only blocked"][c]
    if (r === "regions") return xray.regions[c] ? xray.regions[c].name : ""
    if (r === "ads") return "Ad blocking " + (xray.adblock ? "on" : "off")
    if (r === "dns") return "DNS " + (xray.dns === "custom" ? "own server " + xray.dnsCustom : dnsOptions[dnsIndex()].tooltip)
    if (r === "login") return "Connect at login " + (autoConnect ? "on" : "off")
    if (r === "fragment") return "TLS fragmentation " + (xray.fragment ? "on" : "off")
    if (r === "fragopts") return "Fragmentation parameters"
    if (r === "dnsown") return "Own DNS server " + (xray.dnsCustom || "not set")
    if (r === "traffic" || r === "switches") {
      var pl = (r === "traffic" ? trafficPills : switchPills)[c]
      return pl ? pl.label + " " + (pl.on ? "on" : "off") : ""
    }
    if (r === "auto") return "Auto picks from " + (xray.autoFavorites ? "starred nodes" : "all nodes")
    if (r === "chain") return "First hop " + (xray.chainName || "off")
    if (r === "mux") return "Multiplexing " + (xray.mux ? "on" : "off")
    if (r === "muxc") return "Mux streams " + xray.muxConcurrency
    if (r === "lan") return "Local network access " + (xray.lan ? "on" : "off")
    if (r === "log") return "Log level " + xray.loglevel
    if (r === "ua") return "Subscription user agent " + (xray.userAgent || "default")
    if (r === "subupd") return "Subscriptions update " + subUpdateValue
    if (r === "geo") return "Update geo data"
    if (r === "failover") return "Failover " + (xray.failover ? "on" : "off")
    if (r === "links") return "Open links here " + (xray.handler ? "on" : "off")
    if (r === "check") return "Check where a domain goes"
    if (r === "geodays") return "Geo data refresh " + (xray.geoDays ? "every " + xray.geoDays + " days" : "off")
    if (r === "backup") return c === 1 ? "Paste settings" : "Copy settings"
    if (r === "ruleadd") return "New rule, target " + ruleTargetLabel(ruleTarget)
    if (cursorRule >= 0 && xray.rules[cursorRule]) return "Rule " + xray.rules[cursorRule].value + " " + ruleTargetLabel(xray.rules[cursorRule].target)
    if (r === "subs") return "Update all"
    if (r === "sub") { var s = xray.subs[cursorSub]; return s ? (s.title || s.host) : "" }
    return ""
  }
  onCursorLabelChanged: if (keysUsed && cursorLabel !== "") Qt.callLater(function() {
    var h = chipHint.text.trim()
    Accessible.announce(root.cursorLabel + (h !== "" ? ". " + h : ""))
  })
  readonly property int cursorSub: cursorRow === "sub" ? nodeIndex - visibleNodes.length - 1 : -1
  // The country chip only changes DIRECT's country; hidden while ALL is on.
  // One copy of what each chip does: its tooltip and the keyboard hint line
  // (kept short enough for that single line).
  readonly property var modeOptions: [
    { value: "proxy", label: "PROXY", tooltip: "Apps that use the system proxy go through the VPN · apps already open may need a restart" },
    { value: "tun", label: "TUN", tooltip: xray.tunInstalled ? "All system traffic goes through the VPN"
                                                            : "All traffic via the VPN · first switch asks your password" }
  ]
  // DNS over HTTPS through the tunnel; only TUN sends the system's lookups there
  readonly property var dnsOptions: [
    { value: "cloudflare", label: "CF", tooltip: "Cloudflare 1.1.1.1" },
    { value: "google", label: "GOOGLE", tooltip: "Google 8.8.8.8" },
    { value: "quad9", label: "QUAD9", tooltip: "Quad9 9.9.9.9, blocks known malware domains" },
    { value: "adguard", label: "ADGUARD", tooltip: "AdGuard, filters ads and trackers" },
    { value: "system", label: "SYS", tooltip: "Your network's own DNS, outside the tunnel: your provider sees the lookups" }
  ]
  // the dropdown: presets with their address, and your own server once set
  readonly property var dnsMenu: [
    { value: "cloudflare", label: "Cloudflare" }, { value: "google", label: "Google" },
    { value: "quad9", label: "Quad9" }, { value: "adguard", label: "AdGuard" },
    { value: "system", label: "System" }
  ].concat(xray.dnsCustom ? [{ value: "custom", label: "Own" }] : [])
  function dnsIndex() { return Math.max(0, dnsOptions.findIndex(function(o) { return o.value === xray.dns })) }
  function chooseDns(v) {
    if (xray.busy) { xray.busyRefused(); return }
    if (v === "custom" && xray.dnsCustom === "") { focusDnsField(); return }
    if (v !== xray.dns) xray.setDns(v)
  }
  function focusDnsField() {
    var f = nodeList.headerItem ? nodeList.headerItem.dnsField : null
    if (f) f.forceActiveFocus()
  }
  function toggleAdblock() {
    if (xray.busy) { xray.busyRefused(); return }
    if (xray.geo || xray.adblock) xray.setAdblock(!xray.adblock)
  }

  readonly property var routeOptions: [
    { value: "global", label: "ALL", tooltip: "Everything through the VPN, except your local network" },
    { value: "direct", label: routeRegion ? routeRegion.code.toUpperCase() + " DIRECT" : "DIRECT",
      tooltip: routeRegion ? routeRegion.name + " sites go direct, the rest via the VPN"
                           : "One country's sites go direct, not through the VPN" },
    { value: "blocked", label: "RU BLOCKED", tooltip: "Only sites blocked in Russia go through the VPN, the rest direct · needs Geo UPDATE" }
  ]
  readonly property string routeValue: xray.routing === "ru-blocked" ? "blocked" : xray.region ? "direct" : "global"

  function chipCount(row) {
    return row === "mode" ? 2 : row === "route" ? 4 : row === "dns" ? 1
         : row === "ruleadd" ? ruleTargets.length
         : row === "traffic" ? 3 : row === "switches" ? 2 : row === "fragopts" ? 3
         : row === "auto" ? 2 : row === "log" ? logOptions.length : row === "backup" ? 2 : row === "subupd" ? subUpdateOptions.length : row === "geodays" ? geoDaysOptions.length
         : row === "regions" ? xray.regions.length
         : row === "subs" ? 1
         : row === "sub" ? (xray.subs[cursorSub] && xray.subs[cursorSub].local ? 1 : 2) : 1
  }

  function currentChip(row) {
    if (row === "mode") return xray.mode === "tun" ? 1 : 0
    if (row === "route") return routeValue === "blocked" ? 3 : routeValue === "direct" ? 1 : 0
    if (row === "auto") return xray.autoFavorites ? 1 : 0
    if (row === "log") return optIndex(logOptions, xray.loglevel)
    if (row === "subupd") return optIndex(subUpdateOptions, subUpdateValue)
    if (row === "geodays") return optIndex(geoDaysOptions, String(xray.geoDays))
    if (row === "ruleadd") return Math.max(0, ruleTargets.findIndex(function(o) { return o.value === ruleTarget }))
    if (row !== "regions") return 0
    for (var i = 0; i < xray.regions.length; i++)
      if (xray.routing === xray.regions[i].code + "-direct") return i
    return 0
  }

  function moveChip(dx) {
    if (cursorRow === "") return
    pointerGate.reset()
    chipIndex = Math.max(0, Math.min(chipCount(cursorRow) - 1, chipIndex + dx))
    if (cursorRow === "ruleadd") ruleTarget = ruleTargets[chipIndex].value
  }

  function activateChip() {
    var r = cursorRow
    if (r === "hero") requestToggle()
    else if (r === "settings") toggleSettings()
    else if (r === "mode") chooseMode(chipIndex === 1 ? "tun" : "proxy")
    else if (r === "route") {
      if (chipIndex === 2) regionsOpen = !regionsOpen
      else chooseRoute(routeOptions[chipIndex === 3 ? 2 : chipIndex].value)
    }
    else if (r === "regions" && xray.regions[chipIndex]) pickRegion(xray.regions[chipIndex].code)
    else if (r === "ads") toggleAdblock()
    else if (r === "dns") { var dd2 = nodeList.headerItem ? nodeList.headerItem.dnsDropdown : null; if (dd2) dd2.open() }
    else if (r === "login") toggleAutoConnect()
    else if (r === "fragment") toggleFragment()
    else if (r === "dnsown") focusDnsField()
    else if (r === "auto") guarded(function() { xray.setOption("autofav", chipIndex === 1 ? "on" : "off",
                                                              chipIndex === 1 ? "Auto: starred nodes only" : "Auto: all nodes") })
    else if (r === "chain") focusField("chainField")
    else if (r === "mux") guarded(function() { xray.setOption("mux", xray.mux ? "off" : "on", xray.mux ? "Mux off" : "Mux on") })
    else if (r === "muxc") focusField("muxField")
    else if (r === "lan") guarded(function() { xray.setOption("lan", xray.lan ? "off" : "on", xray.lan ? "Local network access off" : "Local network access on") })
    else if (r === "log") guarded(function() { xray.setOption("loglevel", logOptions[chipIndex].value, "Log level: " + logOptions[chipIndex].label) })
    else if (r === "ua") { var dd = nodeList.headerItem ? nodeList.headerItem.uaDropdown : null; if (dd) dd.open() }
    else if (r === "subupd") guarded(function() { xray.setOption("subupdate", subUpdateOptions[chipIndex].value, "Subscriptions update: " + subUpdateOptions[chipIndex].label) })
    else if (r === "failover") guarded(function() { xray.setOption("failover", xray.failover ? "off" : "on", xray.failover ? "Failover off" : "Failover on") })
    else if (r === "links") guarded(function() { xray.setHandler(!xray.handler) })
    else if (r === "check") focusField("checkField")
    else if (r === "geodays") guarded(function() { var g = geoDaysOptions[chipIndex].value; xray.setOption("geoupdate", g === "0" ? "off" : g, "Geo data: " + geoDaysOptions[chipIndex].tooltip.toLowerCase()) })
    else if (r === "geo") guarded(function() { xray.updateGeo() })
    else if (r === "backup") guarded(function() { xray.settingsClipboard(chipIndex === 1 ? "paste" : "copy") })
    else if (r === "fragopts") focusField(["fragPackets", "fragLength", "fragInterval"][chipIndex] || "fragPackets")
    else if (r === "traffic" && trafficPills[chipIndex]) flipPill(trafficPills[chipIndex].key)
    else if (r === "switches" && switchPills[chipIndex]) flipPill(switchPills[chipIndex].key)
    else if (r === "ruleadd") focusRuleField()
    else if (cursorRule >= 0) removeRule(cursorRule)
    else if (r === "subs") { if (xray.subs.length > 0) xray.updateSubscriptions() }
    else if (r === "sub" && xray.subs[cursorSub]) {
      // the Manual group has no Update: its only chip is Remove
      if (chipIndex === 0 && !xray.subs[cursorSub].local) xray.updateSub(xray.subs[cursorSub].index)
      else armRemove(cursorSub)
    }
  }

  // Removal can't be undone (the URL is a secret the user would have to find
  // again), so it takes a second press on the same spot within 4 s.
  // Armed by the subscription itself (index and host), so a reload in between
  // can never turn the second press into removing another one.
  property string armedSub: ""
  function subKey(s) { return s ? s.index + "|" + (s.url || s.host || "") : "" }
  Timer {
    id: disarmTimer; interval: 4000
    onTriggered: { root.armedSub = ""; Accessible.announce("Remove cancelled") }
  }
  function armRemove(i) {
    var s = xray.subs[i]
    if (!s) return
    if (armedSub === subKey(s)) { armedSub = ""; disarmTimer.stop(); xray.subRemove(s.index); return }
    armedSub = subKey(s)
    disarmTimer.restart()
  }

  // Opening or closing the country grid inserts or removes the row right
  // after ROUTE; keep the cursor on the row it was on (a grid closed under
  // the cursor hands back to its country chip).
  onRegionsOpenChanged: {
    var k = settingRows.indexOf("route") + 1
    if (nodeIndex >= 0 || k === 0) return
    var len = settingRows.length
    var abs = nodeIndex + (regionsOpen ? len - 1 : len + 1)
    if (regionsOpen) { if (abs >= k) abs += 1 }
    else if (abs === k) { abs = k - 1; chipIndex = Math.min(2, chipCount("route") - 1) }
    else if (abs > k) abs -= 1
    nodeIndex = abs - len
  }
  readonly property bool autoConnect: settings ? settings.autoConnect === true : false
  function toggleAutoConnect() { persistSetting("autoConnect", !autoConnect) }
  readonly property string lastNodeKey: settings ? String(settings.lastNodeKey || "") : ""

  // Off while the kill switch holds lets traffic out unprotected, so it takes
  // a second press within 4 s, like Remove. Every on/off path comes here.
  readonly property bool isOn: xray.connected || xray.blocked || xray.dropped
  property bool killArmed: false
  Timer { id: killDisarm; interval: 4000; onTriggered: root.killArmed = false }
  onKillArmedChanged: if (killArmed) xray.flash("Kill switch is holding: press again to turn off, traffic would go direct")
  // on/off from binds goes through the same kill-switch guard as the panel
  function ipcToggle() {
    requestToggle()
    return killArmed ? "kill switch holding: call again within 4 s to let traffic go direct" : "ok"
  }
  function requestToggle() {
    if (xray.blocked && !killArmed) { killArmed = true; killDisarm.restart(); return }
    killArmed = false
    xray.toggleConnection(root.lastNodeKey)
  }

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.4)   // the kit's secondary grey
  // A monochrome theme's "red" is a grey close to `dim`: errors then use the
  // brightest colour so they never read as secondary text.
  readonly property color errorColor: urgent.hslSaturation < 0.2 ? foreground : urgent
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property color hoverFill: bar ? Style.hoverFillFor(bar.foreground, Color.accent) : "transparent"
  readonly property color selectedFill: bar ? Style.selectedFillFor(bar.foreground, Color.accent) : "transparent"

  // "Connected" uses the theme's own green (colors.toml). A monochrome theme's
  // "green" is just another grey (often the secondary text grey itself), so
  // there "on" is drawn in the brightest colour, the foreground; the icon's
  // fill carries the state either way.
  property color onColor: foreground
  function onColorFor(hex) {
    var c = hex ? Qt.color(hex) : Color.accent
    return c.hslSaturation < 0.2 ? foreground : c
  }
  // Where the connection is heading: the switch flips and the shield fills at
  // once while the operation runs (the kit's optimistic toggle).
  readonly property bool onTarget: xray.pending === "connecting" || xray.pending === "switching"
                                   || (xray.connected && xray.pending !== "disconnecting")

  // The shield only claims protection once the tunnel is up; while it comes
  // up it is a bright outline (pulsing at first), off is a dim outline.
  readonly property bool tunnelUp: xray.connected && xray.pending !== "disconnecting"

  readonly property color barIconColor: {
    if (!xray.reachable || xray.blocked) return errorColor
    if (tunnelUp) return onColor
    return foreground            // "off" is carried by the button's kit dimming
  }


  FileView {
    id: themeColors
    path: Color.currentThemePath + "/colors.toml"
    watchChanges: true
    onFileChanged: reload()
    onLoaded: {
      var m = /^\s*green\s*=\s*["']?(#[0-9A-Fa-f]{6})/m.exec(text())
      root.onColor = root.onColorFor(m ? m[1] : "")
    }
  }

  // Theme switches swap the directory behind the path; follow the shell.
  Connections {
    target: Color
    function onAccentChanged() { themeColors.reload() }
  }

  // Flat, filtered node list the cursor walks over; the first row of each
  // group carries the group's header text.
  readonly property var visibleGroups: settingsOpen ? [] : Model.filterNodes(Model.sortGroups(xray.touch ? xray.touch.groups : [], sortByLatency), filterQuery)
  readonly property var visibleRows: {
    var out = []
    for (var g = 0; g < visibleGroups.length; g++) {
      var grp = visibleGroups[g]
      var st = grp.status === undefined || grp.status === null ? "" : String(grp.status).trim()
      var title = grp.subscriptionId === "auto" ? "" : grp.title   // one row needs no header
      var head = { title: title, status: st === "undefined" || st === "null" ? "" : st,
                   expiry: grp.expiry || "", low: grp.low || { usage: false, expiry: false } }
      for (var i = 0; i < grp.nodes.length; i++)
        out.push({ node: grp.nodes[i], title: i === 0 ? title : "", head: head })
    }
    return out
  }
  readonly property var visibleNodes: visibleRows.map(function(r) { return r.node })

  // One empty slot per visible row; delegates read root.visibleRows[index].
  ListModel { id: rowSlots }
  function syncRowSlots() {
    var n = visibleRows.length
    if (rowSlots.count > n) rowSlots.remove(n, rowSlots.count - n)
    if (rowSlots.count < n) {
      var add = []
      for (var i = rowSlots.count; i < n; i++) add.push({ slot: i })
      rowSlots.append(add)
    }
  }
  onVisibleRowsChanged: syncRowSlots()
  Component.onCompleted: syncRowSlots()
  function selectedNode() {
    if (visibleNodes.length === 0) return null
    return visibleNodes[Math.max(0, Math.min(nodeIndex, visibleNodes.length - 1))]
  }

  function ensureCursor() {
    // Clamp from below at 0: an empty list at startup must not park the
    // cursor on a settings row.
    var last = visibleNodes.length - 1 + footerRows
    if (nodeIndex > last) nodeIndex = Math.max(0, last)
  }

  // Home jumps to the switch (disconnect is Home, Enter), End to the last
  // node, PgUp/PgDn move a page. Text fields keep these keys for themselves.
  function jumpCursor(where) {
    var page = Math.max(1, Math.floor(nodeList.height / Style.space(32)))
    var target = where === "home" ? -settingRows.length
               : where === "end" ? visibleNodes.length - 1 + footerRows
               : nodeIndex + (where === "pgdn" ? page : -page)
    root.keysUsed = true
    moveNodeCursor(target - nodeIndex)
  }

  // The flag grid wraps: j/k step to the flag above or below before leaving it.
  function regionStep(dir) {
    var cur = regionRepeater.itemAt(chipIndex)
    if (!cur) return false
    var best = -1, bestDy = 0, bestDx = 0
    for (var i = 0; i < regionRepeater.count; i++) {
      var it = regionRepeater.itemAt(i)
      var dy = (it.y - cur.y) * dir
      if (dy <= 0) continue
      var dx = Math.abs(it.x - cur.x)
      if (best < 0 || dy < bestDy || (dy === bestDy && dx < bestDx)) { best = i; bestDy = dy; bestDx = dx }
    }
    if (best < 0) return false
    chipIndex = best
    return true
  }

  function moveNodeCursor(delta) {
    pointerGate.reset()
    cursorActive = true
    var next = Math.max(-settingRows.length, Math.min(visibleNodes.length - 1 + footerRows, nodeIndex + delta))
    if (next === nodeIndex) return
    nodeIndex = next
    if (nodeIndex < 0) {
      chipIndex = currentChip(cursorRow)
      if (settingsOpen) {
        // ponytail: rows are not items of the list, so the page scrolls in
        // proportion to the row; exact if rows ever become delegates
        var f = (nodeIndex + settingRows.length) / Math.max(1, settingRows.length - 1)
        nodeList.contentY = nodeList.originY + f * Math.max(0, nodeList.contentHeight - nodeList.height)
      } else nodeList.positionViewAtBeginning()
    } else if (nodeIndex < visibleNodes.length) {
      nodeList.positionViewAtIndex(nodeIndex, ListView.Contain)
    } else {
      chipIndex = 0
      subsOpen = true
      nodeList.positionViewAtEnd()
    }
  }

  // Rows appearing or moving under a still pointer send synthetic hovers;
  // only real pointer movement may take the cursor away from the keyboard.
  PointerMoveGate { id: pointerGate; referenceItem: nodeList }

  // Hover moves the cursor but never scrolls: a still pointer near an edge
  // used to make the list creep.
  function setNodeCursor(index) {
    cursorActive = true
    nodeIndex = index
  }

  // Commands take Ctrl so a bare letter is always the start of a search.
  function runCtrl(k) {
    if (k === "t") {
      if (root.filterQuery !== "" && root.visibleNodes.length === 0) xray.flash("Nothing to test: the filter matches no node")
      else if (root.cursorRow === "node" && !xray.testing && root.selectedNode() && root.selectedNode().key !== "auto")
        xray.testNodes([root.selectedNode()])          // the node under the cursor, as right-click
      else xray.testNodes(root.visibleNodes)
    }
    else if (k === "d") speedTestCursor()
    else if (k === "l") xray.openLogs()
    else if (k === "r") xray.updateSubscriptions()             // Ctrl+U/W stay text editing
    else if (k === "o") xray.openFolder()
    else if (k === "a") root.focusSubUrl()
    else if (k === "f") { var fn = root.cursorNodeOrNull(); if (fn) xray.toggleFav(fn) }
    else if (k === "s") {
      var sn = root.cursorNodeOrNull()
      if (xray.share && (!sn || sn.key === xray.share.key)) xray.share = null
      else if (sn) xray.shareNode(sn, "qr")
    }
    else if (k === "c") {
      // a toggle, as the switch and the bar's right-click
      if (!xray.toggleBusy) root.requestToggle()
    }
  }

  // the node under the cursor on its own, else the tunnel; again stops it
  function speedTestCursor() {
    if (xray.speedTesting) { xray.stopSpeed(); return }
    var n = cursorNodeOrNull()
    if (!n && !tunnelUp) { xray.flash("Put the cursor on a node, or connect first"); return }
    guarded(function() { xray.speedTest(n && n.key !== "auto" ? n : null) })
  }

  function startTypeAhead(t) {
    if (settingsOpen) toggleSettings()        // typing filters the nodes
    var search = nodeList.headerItem ? nodeList.headerItem.search : null
    if (!search) return
    if (t !== "/") search.text = t          // the field's onTextChanged sets filterQuery
    search.forceActiveFocus()
    search.cursorPosition = search.text.length
  }

  function activateCursor() {
    if (cursorRow !== "node") { activateChip(); return }
    ensureCursor()
    var node = selectedNode()
    if (node) xray.selectNode(node)
  }

  property real nowMs: Date.now()
  Timer {
    interval: 1000
    repeat: true
    running: (xray.testing || xray.speedTesting) && root.opened
    onTriggered: root.nowMs = Date.now()
  }
  readonly property string elapsedText: {
    var sec = Math.max(0, Math.floor((nowMs - xray.longStartedMs) / 1000))
    return Math.floor(sec / 60) + ":" + ("0" + sec % 60).slice(-2)
  }

  function focusRuleField() {
    var f = nodeList.headerItem ? nodeList.headerItem.ruleField : null
    if (f) f.forceActiveFocus()
  }

  function focusSubUrl() {
    if (settingsOpen) toggleSettings()
    subsOpen = true
    Qt.callLater(function() {
      if (!nodeList.footerItem) return
      nodeList.positionViewAtEnd()
      nodeList.footerItem.subUrl.forceActiveFocus()
    })
  }

  readonly property string fastestKey: Model.fastestKey(visibleNodes)
  // subscriptions whose last update failed, shown on the Update all button
  readonly property int subFailCount: xray.subs.filter(function(s) { return s && s.error }).length
  // nodes whose last latency test failed or timed out, shown on the Test button
  readonly property int failCount: visibleNodes.filter(function(n) {
    return n && n.key !== "auto" && Model.latencyBad(Model.latencyLabel(n.latency))
  }).length
  TextMetrics {
    id: glyphMetrics
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
    text: "󰐽"
  }
  readonly property real rowGlyphWidth: Math.ceil(glyphMetrics.advanceWidth)
  TextMetrics {
    id: confirmMetrics
    font.family: root.fontFamily
    font.pixelSize: Style.font.body
    text: "Confirm"
  }
  // One height for every chip, button and field: compact, and nothing in a
  // row sits taller than its neighbour.
  FontMetrics { id: ctlMetrics; font.family: root.fontFamily; font.pixelSize: Style.font.caption }
  readonly property real ctlHeight: Math.ceil(ctlMetrics.height) + 2 * Style.space(4)
  readonly property real rowTextInset: Style.space(8) + rowGlyphWidth + Style.space(8)
  TextMetrics {
    id: latencyMetrics
    font.family: root.fontFamily
    font.pixelSize: Style.font.bodySmall
    font.bold: true
    text: "󰉁 9999ms"
  }
  readonly property real latencyCellWidth: Math.ceil(latencyMetrics.advanceWidth)

  function importSub() {
    var field = nodeList.footerItem ? nodeList.footerItem.subUrl : null
    if (field) xray.importUrl(field.text.trim(), function(ok) { if (ok) field.text = "" })
  }

  function persistSetting(key, value) {
    if (!root.bar || !root.bar.shell || typeof root.bar.shell.updateEntryInline !== "function") return
    var entry = { id: root.moduleName }
    for (var k in settings) if (k !== "id") entry[k] = settings[k]
    entry[key] = value
    root.bar.shell.updateEntryInline(root.moduleName, entry)
  }

  // Node, subscription and error strings come from the subscription provider:
  // every Text here is PlainText (as in the kit), so markup such as <img src>
  // can never render or make the shell fetch a URL outside the tunnel.
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onOpenedChanged: if (opened) {
    cursorActive = false
    keysUsed = false
    subsOpen = false
    filterQuery = ""                     // every open starts from the whole list
    if (nodeList.headerItem) nodeList.headerItem.search.text = ""
    nodeIndex = 0
    pointerGate.reset()
    regionsOpen = false
    nodeList.positionViewAtBeginning()
    xray.refresh()
    Qt.callLater(function() { if (root.firstRun) root.focusSubUrl(); else keyCatcher.forceActiveFocus() })
  }
  onVisibleNodesChanged: ensureCursor()

  Service {
    id: xray
    settings: root.settings
    panelRef: root
    panelOpen: root.opened
  }

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refreshNow(): string { xray.refresh(); return "ok" }
    function status(): string { return xray.heroSummary }
    function connect(): string { return root.isOn ? "already on" : root.ipcToggle() }
    function disconnect(): string { return root.isOn ? root.ipcToggle() : "already off" }
    function toggleProxy(): string { return root.ipcToggle() }
    function select(name: string): string {
      var q = String(name || "").trim().toLowerCase()
      if (q === "") return "usage: select <part of a node name>"
      var nodes = xray.touch ? xray.touch.nodes : []
      for (var i = 0; i < nodes.length; i++) {
        if (nodes[i].name.toLowerCase().indexOf(q) !== -1) { xray.connectNode(nodes[i]); return "ok" }
      }
      return "no node matches: " + name
    }
    function test(): string { xray.testNodes(xray.touch ? xray.touch.nodes : []); return "ok" }
    function updateSubs(): string { xray.updateSubscriptions(); return "ok" }
    function subRemove(index: string): string { xray.subRemove(index); return "ok" }
    function mode(m: string): string { xray.setMode(m); return "ok" }
    function routing(p: string): string { xray.setRouting(p); return "ok" }
    function adblock(on: string): string { xray.setAdblock(on === "on" || on === "true"); return "ok" }
    function tunSetup(): string { xray.tunSetup(false); return "ok" }
    function openFolder(): string { xray.openFolder(); return "ok" }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    dimmed: xray.reachable && !root.onTarget
    // an action started from the bar (right-click) reports back here too
    tooltipText: (xray.errorText !== "" ? "󰀦 " + xray.errorText + "\n" : "")
                 + (xray.pending !== "" ? xray.actionStatus
                    : xray.heroSummary + " · right-click to " + (root.isOn ? "turn off" : "connect"))
    iconComponent: Component {
      Item {
        XrayIcon {
          anchors.centerIn: parent
          iconSize: Style.space(14)
          color: root.barIconColor
          // outline in every state: brightness says on/off (the button dims
          // when off), a fill at bar size only blurs the arches
          filled: false
          simple: true
          warning: !xray.reachable || xray.errorText !== "" || xray.subsTrouble
          badgeColor: root.errorColor
          // ~11 s of a slow breath, then a still bright outline: a password
          // prompt can take minutes and must not blink in the bar all along.
          SequentialAnimation on opacity {
            running: xray.pending !== ""
            loops: 8
            alwaysRunToEnd: true
            NumberAnimation { to: 0.45; duration: 700; easing.type: Easing.InOutSine }
            NumberAnimation { to: 1.0; duration: 700; easing.type: Easing.InOutSine }
          }
        }
      }
    }
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton) root.requestToggle()
      else if (buttonCode === Qt.MiddleButton) xray.refresh()
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
    // tighter top and bottom; the sides keep the kit's popup padding (below)
    padding: Style.space(8)
    contentWidth: panel.fittedContentWidth(Style.space(360))
    contentHeight: panel.fittedContentHeight(pinned.height + Style.space(12) + nodeList.contentHeight,
                                             Style.space(620))

    PanelKeyCatcher {
      id: keyCatcher
      readonly property real sideInset: Math.max(0, Style.spacing.popupPadding - panel.padding)
      // Inline editors get every key (kit contract); they handle Up/Down/Enter/Esc themselves.
      blocked: (nodeList.headerItem !== null && (nodeList.headerItem.search.activeFocus || nodeList.headerItem.ruleField.activeFocus
                                                 || nodeList.headerItem.dnsField.activeFocus
                                                 || nodeList.headerItem.chainField.activeFocus
                                                 || nodeList.headerItem.muxField.activeFocus
                                                 || nodeList.headerItem.checkField.activeFocus
                                                 || nodeList.headerItem.uaDropdown.popupOpen || nodeList.headerItem.dnsDropdown.popupOpen
                                                 || nodeList.headerItem.fragFocused))
               || (nodeList.footerItem !== null && nodeList.footerItem.subUrl.activeFocus)
      anchors.fill: parent
      anchors.leftMargin: sideInset
      anchors.rightMargin: sideInset
      onMoveRequested: function(dx, dy) {
        root.keysUsed = true
        if (!root.cursorActive) { root.cursorActive = true; return }
        if (dy !== 0) { if (!(root.cursorRow === "regions" && root.regionStep(dy))) root.moveNodeCursor(dy > 0 ? 1 : -1) }
        else if (dx !== 0) root.moveChip(dx)
      }
      // Enter with no cursor shows it first instead of doing nothing.
      onActivateRequested: {
        root.keysUsed = true
        if (root.cursorActive) root.activateCursor(); else root.cursorActive = true
      }
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        var legendShown = root.keyboardUser && !root.legendHidden
        root.keysUsed = true
        var code = t.charCodeAt(0)
        if (code > 0 && code < 27) { root.runCtrl(String.fromCharCode(96 + code)); return }   // Ctrl+T = "\x14"
        if (t === "?") { root.legendHidden = legendShown; return }
        if (/^[^\s\x00-\x1f]$/.test(t)) root.startTypeAhead(t)          // "/" just opens the field
      }
      // the kit reserves x for delete; nothing here deletes, so it types
      onDeleteRequested: { root.keysUsed = true; root.startTypeAhead("x") }

      Shortcut { sequence: "Home"; enabled: root.opened && !keyCatcher.blocked; onActivated: root.jumpCursor("home") }
      Shortcut { sequence: "End"; enabled: root.opened && !keyCatcher.blocked; onActivated: root.jumpCursor("end") }
      Shortcut { sequence: "PgDown"; enabled: root.opened && !keyCatcher.blocked; onActivated: root.jumpCursor("pgdn") }
      Shortcut { sequence: "PgUp"; enabled: root.opened && !keyCatcher.blocked; onActivated: root.jumpCursor("pgup") }

      // One scroll view for the whole panel. Only the node rows are
      // virtualized (1000 rows in a Column cost ~0.3 s per rebuild); the
      // controls above and the subscriptions below ride along as header and
      // footer so everything still scrolls together.
      // The hero and the status line stay put; only what is below scrolls,
      // so the result of an action at the bottom is never drawn out of view.
      Column {
        id: pinned
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: Style.space(4)

        PanelHero {
          id: hero
          width: parent.width
          title: xray.heroTitle
          meta: xray.heroState + (xray.connected && xray.exitIp !== ""
                ? "  ·  " + Model.flagOf(xray.exitCountry) + " " + xray.exitIp : "")
          foreground: root.foreground
          fontFamily: root.fontFamily
          iconOpacity: root.onTarget ? 1.0 : 0.5
          // a narrow box: the icon close to the edge and to the title
          iconComponent: Component {
            Item {
            implicitWidth: heroIcon.width + Style.space(6)
            implicitHeight: heroIcon.height
            // the keys live here for mouse users, out of the way
            MouseArea { id: heroIconHover; anchors.fill: parent; hoverEnabled: true }
            PanelToolTip {
              visible: heroIconHover.containsMouse
              text: "Keys: Ctrl+C on/off · type to filter · j/k move · Enter apply · ? all keys"
              fontFamily: root.fontFamily
            }
            XrayIcon {
              id: heroIcon
              anchors.centerIn: parent
              iconSize: Math.round(Style.font.display * 1.25)
              color: root.tunnelUp ? root.onColor : hero.foreground
              filled: root.tunnelUp
              half: xray.mode !== "tun"   // proxy covers only some apps
              warning: !xray.reachable || xray.errorText !== "" || xray.subsTrouble
              badgeColor: root.errorColor
            }
            }
          }
          trailingControl: Component {
            ToggleSwitch {
              id: powerSwitch
              visible: !root.firstRun && xray.reachable   // nothing to connect to (yet)
              checked: root.onTarget || xray.blocked || xray.dropped
              busy: xray.toggleBusy
              opacity: xray.toggleBusy ? 0.5 : 1.0
              hasCursor: root.cursorRow === "hero"
              foreground: hero.foreground
              onToggled: root.requestToggle()
              onHovered: function(h) { if (h) root.cursorActive = false }
              Accessible.role: Accessible.CheckBox
              Accessible.name: "VPN connection, " + (xray.blocked ? "blocked by the kill switch"
                               : xray.dropped ? "dropped, reconnecting"
                               : root.tunnelUp ? (xray.mode === "tun" ? "on, whole system" : "on, proxy apps only")
                               : root.onTarget ? "connecting" : "off")
              Accessible.checked: checked
              Accessible.focusable: true
              Accessible.focused: hasCursor

              PanelToolTip {
                visible: powerSwitch.containsMouse
                text: root.killArmed ? "Click again: traffic goes direct, unprotected"
                      : xray.blocked ? "Kill switch: nothing leaks while it reconnects. Turning off lets traffic go direct"
                      : xray.connected || xray.dropped ? "Disconnect (Ctrl+C)"
                      : xray.connectTarget ? "Connect to " + xray.connectTarget.name + " (Ctrl+C)" : "Add a subscription or a server first"
                fontFamily: root.fontFamily
              }
            }
          }
        }

        // One status slot: the running action, else the last error (may wrap,
        // with a way to the journal), else live traffic.
        RowLayout {
          id: statusRow
          readonly property bool live: xray.connected && xray.traffic !== null
          readonly property string errText: xray.errorText !== "" ? xray.errorText : "The xray manager is not answering"
          readonly property string kind: xray.actionStatus !== "" && xray.pending === "" ? "action"
                                       : xray.errorText !== "" && !xray.blocked && !xray.dropped ? "error"
                                       : !xray.reachable ? "error"
                                       : root.firstRun || !xray.connected ? "none" : "traffic"
          visible: kind !== "none"
          width: parent.width
          spacing: Style.space(8)

          Text {
            textFormat: Text.PlainText
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            text: statusRow.kind === "action" ? xray.actionStatus
                  : statusRow.kind === "error" ? "󰀦 " + statusRow.errText
                  : !statusRow.live ? "Measuring traffic…"
                  : "󰁅 " + Model.formatSpeed(xray.traffic.downSpeed)
                    + "  󰁝 " + Model.formatSpeed(xray.traffic.upSpeed)
                    // totals since connect: tray-arrow glyphs, unlike the speed arrows
                    + " · 󰇚 " + Model.formatBytes(xray.traffic.downTotal)
                    + " 󰕒 " + Model.formatBytes(xray.traffic.upTotal)
            color: statusRow.kind === "error" ? root.errorColor
                   : statusRow.kind === "traffic" && statusRow.live ? root.foreground : root.dim
            font.family: root.fontFamily
            font.pixelSize: statusRow.kind === "traffic" ? Style.font.caption : Style.font.bodySmall
            wrapMode: statusRow.kind === "error" ? Text.WordWrap : Text.NoWrap
            elide: statusRow.kind === "error" ? Text.ElideNone : Text.ElideRight
            Accessible.role: Accessible.StaticText
            Accessible.name: statusRow.kind === "error" ? "Error: " + statusRow.errText
                             : statusRow.kind === "action" ? xray.actionStatus
                             : statusRow.live ? "Download " + Model.formatSpeed(xray.traffic.downSpeed)
                                                + ", upload " + Model.formatSpeed(xray.traffic.upSpeed)
                                                + ", total down " + Model.formatBytes(xray.traffic.downTotal)
                                                + ", up " + Model.formatBytes(xray.traffic.upTotal)
                             : "Measuring traffic"
            onTextChanged: if (statusRow.kind === "error" || statusRow.kind === "action")
                             Accessible.announce(statusRow.kind === "error" ? "Error: " + statusRow.errText : xray.actionStatus)
          }

          TextActionButton {
            visible: !xray.reachable
            label: "Doctor"
            tooltip: "Check xray, geo data, TUN and polkit in a terminal"
            Layout.alignment: Qt.AlignTop
            onClicked: xray.openDoctor()
          }

          TextActionButton {
            visible: statusRow.kind === "error"
            label: "Logs"
            tooltip: "Open the xray journal in a terminal"
            Layout.alignment: Qt.AlignTop
            onClicked: xray.openLogs()
          }
        }

        // Keyboard users never see hover tooltips: the chip under the
        // cursor explains itself here (and to a screen reader). One fixed
        // line below the settings, kept once the keyboard is in use, so
        // no row moves when the cursor crosses them.
        Text {
          id: chipHint
          textFormat: Text.PlainText
          // only while the cursor is on a row it explains: no blank line otherwise
          visible: root.keyboardUser && !root.firstRun && text.trim() !== ""
          width: parent.width
          text: {
            var r = root.cursorRow, c = root.chipIndex
            if (r === "mode") return root.modeOptions[c].tooltip
            if (r === "route") return c === 2 ? "Change the direct country" : root.routeOptions[c === 3 ? 2 : c].tooltip
            if (r === "settings") return root.settingsOpen ? "Enter goes back to the nodes" : "Enter opens the settings"
            if (r === "traffic" || r === "switches") {
              var pp = (r === "traffic" ? root.trafficPills : root.switchPills)[c]
              return pp ? pp.tooltip + " · Enter toggles" : ""
            }
            if (r === "fragopts") return ["packets: tlshello or 1-3", "length: bytes per piece", "interval: ms between pieces"][c] + " · Enter edits"
            var hintOpts = { auto: root.autoOptions, log: root.logOptions, backup: root.backupOptions, subupd: root.subUpdateOptions, geo: root.geoOptions, geodays: root.geoDaysOptions }
            if (hintOpts[r]) {
              var o = hintOpts[r]
              return o[c] ? o[c].tooltip : ""
            }
            if (r === "chain") return "Enter edits · traffic goes through this node first"
            if (r === "mux") return "Fewer handshakes · not Vision, XHTTP, Hysteria2"
            if (r === "muxc") return "Enter edits · streams per connection, 1-1024"
            if (r === "lan") return "Your network can use this VPN, with a password"
            if (r === "failover") return "Switch to the fastest node when yours stops answering · not with Auto"
            if (r === "links") return "Clicked vless://, hy2://, happ://add/… links import here"
            if (r === "check") return "Enter types · a domain or an IP, Enter checks"
            if (r === "ua") return "Enter opens the list · the next update uses it"
            if (r === "dnsown") return "Enter edits · IP or https/tls/quic URL"
            if (r === "fragopts") return "Enter edits · in a field Enter applies, Esc restores"
            if (r === "fragment") return "Splits the TLS handshake against DPI · not REALITY"
            if (r === "ruleadd") return root.ruleTargets[c].tooltip + " · Enter to type"
            if (root.cursorRule >= 0) return "Enter removes this rule"
            if (r === "login") return "Connects to the selected node when you log in"
            if (r === "dns") return "Enter opens the list" + (xray.mode === "tun" ? "" : " · used in TUN mode")
            if (r === "ads") return xray.geo ? "ADBLOCK: known ad and tracker domains" : "ADBLOCK needs the geo data packages"
            if (r === "hero") return root.killArmed ? "Enter again: traffic goes direct, unprotected"
                                      : xray.blocked ? "Waiting is safe: nothing leaks. Enter, then Enter again, turns it off"
                                      : xray.connected ? "Enter disconnects" : "Enter connects"
            return ""
          }
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          elide: Text.ElideRight
        }

        // Keys in three groups, pinned so they are never a list's length
        // away. Shown once the keyboard is used (and on first run); `?`
        // hides or shows them. Before that, the hero icon's tooltip has them.
        Column {
          visible: root.firstRun || (xray.reachable && root.keyboardUser && !root.legendHidden)
          width: parent.width
          spacing: Style.space(4)

          Repeater {
            model: root.firstRun ? [["", "Enter adds it · Esc twice closes"]]
                   : root.filterFocused ? [["FILTER", "↑/↓ · Enter select · Ctrl+T test · Esc clear"]]
                   : root.urlFocused ? [["URL", "Enter adds it · Esc back to the list"]]
                   : [["MOVE", "j/k · h/l · Enter apply · Home switch · ? hide"],
                      ["ACT", "Ctrl+C on/off · Ctrl+T test · Ctrl+R update"],
                      ["NODE", "Ctrl+F star · Ctrl+S share (QR) · Ctrl+D speed"],
                      ["MANAGE", "Ctrl+A add sub · Ctrl+O folder · Ctrl+L logs"]]
            delegate: RowLayout {
              required property var modelData
              width: parent ? parent.width : 0
              spacing: Style.space(8)

              PanelSectionHeader {
                visible: modelData[0] !== ""
                text: modelData[0]
                Layout.preferredWidth: root.settingLabelWidth
                Layout.alignment: Qt.AlignTop
                foreground: root.foreground
                fontFamily: root.fontFamily
              }
              Text {
                textFormat: Text.PlainText
                Layout.fillWidth: true
                text: modelData[1]
                wrapMode: Text.WordWrap
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
              }
            }
          }
        }

        PanelSeparator { visible: xray.reachable && !root.firstRun; foreground: root.foreground }
      }

      ListView {
        id: nodeList
        anchors.top: pinned.bottom
        anchors.topMargin: Style.space(4)
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height
        reuseItems: true
        spacing: Style.space(2)
        currentIndex: -1                   // the panel keeps its own cursor (nodeIndex)
        // The header grows upward (country grid): a view resting
        // at the top stays at the top instead of pushing the hero out of sight.
        property real _prevOriginY: 0
        onOriginYChanged: {
          if (Math.abs(contentY - _prevOriginY) < 1) contentY = originY
          _prevOriginY = originY
        }
        keyNavigationEnabled: false
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
        // rowSlots only grows/shrinks at the tail: swapping the model would
        // reset the view and rebuild header and footer, dropping focus and
        // half-typed text in the filter and URL fields.
        model: rowSlots

        header: Column {
          property alias search: searchField
          property alias ruleField: ruleField
          property alias dnsField: dnsField
          property alias chainField: chainRow.field
          property alias muxField: muxRow.field
          property alias checkField: checkRow.field
          property alias uaDropdown: uaDropdown
          property alias dnsDropdown: dnsDropdown
          property alias fragPackets: fragPacketsField
          property alias fragLength: fragLengthField
          property alias fragInterval: fragIntervalField
          readonly property bool fragFocused: fragPackets.activeFocus || fragLength.activeFocus || fragInterval.activeFocus
          width: nodeList.width
          spacing: Style.space(4)
          bottomPadding: Style.space(2)

          // Mode and route are set-and-forget: a compact label/chips form that
          // stays quieter than the connect switch and the node list.
          RowLayout {
            visible: xray.reachable && !root.firstRun
            width: parent.width
            spacing: Style.space(8)

            PanelSectionHeader {
              text: "SETTINGS"
              Layout.preferredWidth: root.settingLabelWidth
              Layout.alignment: Qt.AlignVCenter
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            TextActionButton {
              label: root.settingsOpen ? "󰁍  NODES" : root.settingsSummary + "  󰅂"
              a11yName: root.settingsOpen ? "Back to the nodes" : "Open settings. Now: " + root.settingsSummary
              tooltip: root.settingsOpen ? "Back to the nodes" : "Mode, route, DNS, ad blocking, fragmentation, rules, login"
              hasCursor: root.cursorRow === "settings"
              onClicked: root.toggleSettings()
            }

            Item { Layout.fillWidth: true }
          }

          // A page of its own, in groups: each title names what its rows
          // change, rows carry a quiet label and their control; what a row
          // does lives in its tooltip and the keyboard hint line.
          Column {
            visible: xray.reachable && !root.firstRun && root.settingsOpen
            width: parent.width
            spacing: nodeList.spacing      // the node list's rhythm

            SectionTitle { text: "CONNECTION"; first: true }

            RowLayout {
              width: parent.width
              spacing: Style.space(8)
              RowLabel { text: "Mode" }
              ChipGroup {
                options: root.modeOptions
                value: xray.mode
                cursorIndex: root.cursorRow === "mode" ? root.chipIndex : -1
                // the kit's chips carry no accessible names; the group says the state
                Accessible.role: Accessible.Grouping
                Accessible.name: "Mode: " + (xray.mode === "tun" ? "TUN, all system traffic" : "proxy")
                Accessible.description: "Options: proxy, TUN. h and l switch"
                Accessible.focusable: true
                Accessible.focused: cursorIndex >= 0
                opacity: xray.busy ? 0.45 : 1.0
                onChanged: function(v) { root.chooseMode(v) }
                onHovered: function(i, h) { if (h) root.cursorActive = false }
              }

              Item { Layout.fillWidth: true }
            }

            RowLayout {
              width: parent.width
              spacing: Style.space(8)
              RowLabel { text: "Route" }
              ChipGroup {
                options: root.routeOptions.slice(0, 2)
                value: root.routeValue
                cursorIndex: root.cursorRow === "route" && root.chipIndex < 2 ? root.chipIndex : -1
                Accessible.role: Accessible.Grouping
                Accessible.name: "Route: " + (xray.routing === "ru-blocked" ? "only blocked sites through the VPN" : xray.region ? xray.region.name + " sites go direct" : "everything through the VPN")
                Accessible.description: "Options: all through the VPN, one country direct, only blocked sites. h and l switch"
                Accessible.focusable: true
                Accessible.focused: cursorIndex >= 0
                opacity: xray.busy ? 0.45 : 1.0
                onChanged: function(v) { root.chooseRoute(v) }
                onHovered: function(i, h) { if (h) root.cursorActive = false }
              }

              Button {
                text: root.regionsOpen ? "󰅃" : "󰅀"
                tooltipText: "Change the direct country"
                bordered: true
                opacity: xray.busy ? 0.45 : 1.0
                hasCursor: root.cursorRow === "route" && root.chipIndex === 2
                Accessible.focusable: true
                Accessible.focused: hasCursor
                enabled: xray.regions.length > 0
                fontFamily: root.fontFamily
                fontSize: Style.font.caption
                implicitHeight: root.ctlHeight
                onClicked: root.regionsOpen = !root.regionsOpen
                onHovered: function(h) { if (h) root.cursorActive = false }
                Accessible.role: Accessible.Button
                Accessible.name: root.regionsOpen ? "Hide the country list" : "Change the direct country"
              }

              // after the arrow: the arrow picks DIRECT's country, not this
              ChipGroup {
                options: root.routeOptions.slice(2)
                value: root.routeValue
                cursorIndex: root.cursorRow === "route" && root.chipIndex === 3 ? 0 : -1
                opacity: xray.busy ? 0.45 : 1.0
                onChanged: function(v) { root.chooseRoute(v) }
                onHovered: function(i, h) { if (h) root.cursorActive = false }
              }

              Item { Layout.fillWidth: true }
            }

            Flow {
              visible: root.regionsOpen
              x: root.settingLabelWidth + Style.space(8)
              width: parent.width - x
              spacing: Style.space(4)

              Repeater {
                id: regionRepeater
                model: xray.regions
                delegate: Button {
                  required property var modelData
                  required property int index
                  text: modelData.flag + " " + modelData.code.toUpperCase()
                  hasCursor: root.cursorRow === "regions" && root.chipIndex === index
                  Accessible.role: Accessible.Button
                  Accessible.name: modelData.name + (selected ? ", direct now" : "")
                  Accessible.focusable: true
                  Accessible.focused: hasCursor
                  tooltipText: modelData.name + ": sites and IPs go direct"
                               + (xray.geo ? "" : " (domains only: no geo data installed)")
                  bordered: true
                  selected: xray.routing === modelData.code + "-direct"
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                  fontSize: Style.font.caption
                  implicitHeight: root.ctlHeight
                  onClicked: root.pickRegion(modelData.code)
                  onHovered: function(h) { if (h) { root.cursorActive = false; root.regionHover = index } }
                }
              }
            }

            Text {
              textFormat: Text.PlainText
              visible: root.regionsOpen
              leftPadding: root.settingLabelWidth + Style.space(8)
              width: parent.width
              text: {
                var i = root.cursorRow === "regions" ? root.chipIndex : (root.cursorActive ? -1 : root.regionHover)
                var r = i >= 0 ? xray.regions[i] : null
                if (r) return r.name + ": its sites and IPs go direct" + (xray.geo ? "" : " (domains only, no geo data)")
                return root.routeRegion ? "Direct now: " + root.routeRegion.name : "Pick the country whose sites go direct"
              }
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              wrapMode: Text.WordWrap
            }

            SettingToggle {
              label: "Login"
              a11yName: "Connect at login"
              checked: root.autoConnect
              hasCursor: root.cursorRow === "login"
              note: "Connect when you log in"
              onFlip: root.toggleAutoConnect()
            }

            SectionTitle { text: "DNS"; trailing: xray.mode === "tun" ? "" : "used in TUN" }

            RowLayout {
              width: parent.width
              spacing: Style.space(8)
              RowLabel { text: "Server" }
              Dropdown {
                id: dnsDropdown
                showLabel: false
                rowHeight: root.ctlHeight
                popupRowHeight: root.ctlHeight
                Layout.preferredWidth: Style.space(150)
                options: root.dnsMenu
                value: xray.dns
                foreground: root.foreground
                fontFamily: root.fontFamily
                hasCursor: root.cursorRow === "dns"
                onHovered: function(h) { if (h) root.cursorActive = false }
                onChanged: function(v) { root.chooseDns(v) }
              }
              Item { Layout.fillWidth: true }
            }

            // Own server: Enter switches DNS to it; the check mark says it is in use.
            RowLayout {
              width: parent.width
              spacing: Style.space(8)
              RowLabel { text: "Own" }
            RowField {
              id: dnsField
              Layout.fillWidth: true
              icon: xray.dns === "custom" ? "󰄬" : "󰇖"
              text: xray.dnsCustom
              placeholderText: "9.9.9.9 or https://…"
              maximumLength: 200
              Accessible.name: "Own DNS server"
              Keys.onPressed: function(event) {
                if (event.key === Qt.Key_Escape) {
                  text = xray.dnsCustom
                  keyCatcher.forceActiveFocus()
                  event.accepted = true
                } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                  if (xray.busy) xray.busyRefused()
                  else if (text.trim() !== "") xray.setDns("custom", text.trim())
                  keyCatcher.forceActiveFocus()
                  event.accepted = true
                }
              }
            }
            }

            SectionTitle { text: "TRAFFIC" }

            SettingToggle {
              label: "Adblock"
              a11yName: "Ad blocking"
              checked: xray.adblock
              usable: xray.geo || xray.adblock
              busy: xray.busy
              hasCursor: root.cursorRow === "ads"
              note: xray.geo ? "Blocks known ad and tracker domains"
                             : "Needs geo data: install v2ray-geoip and v2ray-domain-list-community"
              onFlip: root.toggleAdblock()
            }

            SettingToggle {
              label: "Fragment"
              a11yName: "TLS fragmentation"
              checked: xray.fragment
              busy: xray.busy
              hasCursor: root.cursorRow === "fragment"
              note: "Splits the TLS handshake against DPI · not REALITY"
              onFlip: root.toggleFragment()
            }

            // Fragment's three parameters side by side, Mux's stream count:
            // shown only while their pill is on.
            RowLayout {
              visible: xray.fragment
              width: parent.width
              spacing: Style.space(4)
              RowLabel { text: "Pieces"; leftPadding: Style.space(10) }
              FragField { id: fragPacketsField; key: "packets"; hint: "tlshello"; col: 0 }
              FragField { id: fragLengthField; key: "length"; hint: "100-200"; col: 1 }
              FragField { id: fragIntervalField; key: "interval"; hint: "10-20"; col: 2 }
            }

            SettingToggle {
              label: "Mux"
              a11yName: "Multiplexing"
              checked: xray.mux
              busy: xray.busy
              hasCursor: root.cursorRow === "mux"
              note: "Fewer handshakes · not Vision, XHTTP, Hysteria2"
              onFlip: root.guarded(function() { xray.setOption("mux", xray.mux ? "off" : "on") })
            }

            FieldRow {
              id: muxRow
              sub: true
              visible: xray.mux
              label: "Streams"
              value: String(xray.muxConcurrency)
              hint: "1-1024"
              row: "muxc"
              onSubmitted: function(t) { if (/^\d+$/.test(t)) root.guarded(function() { xray.setOption("mux", t) }) }
            }

            SectionTitle { text: "NODES" }

            ChipRow {
              label: "Auto"
              options: root.autoOptions
              value: xray.autoFavorites ? "fav" : "all"
              row: "auto"
              onChanged: function(v) { root.guarded(function() { xray.setOption("autofav", v === "fav" ? "on" : "off") }) }
            }

            FieldRow {
              id: chainRow
              label: "Chain"
              value: xray.chainName
              hint: "off · type a node name"
              icon: "󰌷"
              row: "chain"
              onSubmitted: function(t) { root.guarded(function() { xray.setChain(t === "" ? "off" : t) }) }
            }

            ChipRow {
              label: "Update"
              options: root.subUpdateOptions
              value: root.subUpdateValue
              row: "subupd"
              onChanged: function(v) { root.guarded(function() { xray.setOption("subupdate", v, "Subscriptions update: " + v) }) }
            }

            SettingToggle {
              label: "Failover"
              a11yName: "Switch nodes when yours stops answering"
              checked: xray.failover
              busy: xray.busy
              hasCursor: root.cursorRow === "failover"
              note: "When your node stops answering, switch to the fastest one that does · not with Auto"
              onFlip: root.guarded(function() { xray.setOption("failover", xray.failover ? "off" : "on", xray.failover ? "Failover off" : "Failover on") })
            }

            SectionTitle { text: "SYSTEM" }

            SettingToggle {
              label: "LAN"
              a11yName: "Local network access"
              checked: xray.lan
              busy: xray.busy
              hasCursor: root.cursorRow === "lan"
              note: "Your network can use this VPN, with a password"
              onFlip: root.guarded(function() { xray.setOption("lan", xray.lan ? "off" : "on") })
            }

            // What a phone needs, one fact per line so nothing runs off the edge.
            Column {
              visible: xray.lan && !!xray.lanInfo
              width: parent.width
              leftPadding: root.settingLabelWidth + Style.space(8)
              spacing: Style.space(2)
              Repeater {
                model: xray.lanInfo ? [
                  ["address", (xray.lanInfo.ip || "no address")],
                  ["socks5", String(xray.lanInfo.socks)], ["http", String(xray.lanInfo.http)],
                  ["user", xray.lanInfo.user], ["password", xray.lanInfo.pass]] : []
                delegate: Row {
                  required property var modelData
                  spacing: Style.space(8)
                  Text {
                    textFormat: Text.PlainText
                    width: Style.space(56)
                    text: modelData[0]
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall
                  }
                  TextEdit {
                    textFormat: TextEdit.PlainText
                    readOnly: true
                    selectByMouse: true          // copy the password by hand
                    text: modelData[1]
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall
                  }
                }
              }
            }

            SettingToggle {
              label: "Links"
              a11yName: "Open vless and happ links here"
              checked: xray.handler
              busy: xray.busy
              hasCursor: root.cursorRow === "links"
              note: "Clicked vless://, hy2://, happ://add/… links import here"
              onFlip: root.guarded(function() { xray.setHandler(!xray.handler) })
            }

            ChipRow {
              label: "Log"
              options: root.logOptions
              value: xray.loglevel
              row: "log"
              onChanged: function(v) { root.guarded(function() { xray.setOption("loglevel", v) }) }
            }

            RowLayout {
              width: parent.width
              spacing: Style.space(8)
              RowLabel { text: "UA" }
              Dropdown {
                id: uaDropdown
                showLabel: false
                rowHeight: root.ctlHeight            // as tall as the chips beside it
                popupRowHeight: root.ctlHeight
                Layout.preferredWidth: Style.space(150)
                options: root.uaOptions
                value: xray.userAgent
                foreground: root.foreground
                fontFamily: root.fontFamily
                hasCursor: root.cursorRow === "ua"
                onHovered: function(h) { if (h) root.cursorActive = false }
                onChanged: function(v) { root.guarded(function() { xray.setOption("ua", v === "" ? "default" : v, "User-Agent saved: used at the next update") }) }
              }
              Item { Layout.fillWidth: true }
            }

            ChipRow {
              label: "Geo"
              options: root.geoOptions
              row: "geo"
              trailing: xray.geoOwn ? "downloaded" : xray.geo ? "distro" : "missing"
              onChanged: function(v) { root.guarded(function() { xray.updateGeo() }) }
            }

            ChipRow {
              label: "Every"
              sub: true
              options: root.geoDaysOptions
              value: String(xray.geoDays)
              row: "geodays"
              onChanged: function(v) { root.guarded(function() { xray.setOption("geoupdate", v === "0" ? "off" : v, "Geo data: " + (v === "0" ? "only by hand" : "every " + v + " days")) }) }
            }

            ChipRow {
              label: "Backup"
              options: root.backupOptions
              value: ""
              row: "backup"
              onChanged: function(v) { root.guarded(function() { xray.settingsClipboard(v) }) }
            }

            SectionTitle { text: "RULES"; trailing: xray.rules.length ? String(xray.rules.length) : "" }

            // Where would this go? The config's own rules answer, in order.
            FieldRow {
              id: checkRow
              label: "Check"
              hint: "domain or IP: where does it go?"
              icon: "󰍉"
              row: "check"
              onSubmitted: function(t) { xray.checkRoute(t) }
            }

            Text {
              textFormat: Text.PlainText
              visible: !!xray.routeCheck
              width: parent.width
              leftPadding: root.settingLabelWidth + Style.space(8)
              wrapMode: Text.Wrap
              text: !xray.routeCheck ? "" : xray.routeCheck.via === "" ? xray.routeCheck.match
                    : xray.routeCheck.target + " → " + ({ vpn: "VPN", direct: "DIRECT", block: "BLOCK" })[xray.routeCheck.via]
                      + " · " + xray.routeCheck.match
                      + (xray.routeCheck.ips && xray.routeCheck.ips.length ? " · " + xray.routeCheck.ips[0] : "")
              color: !xray.routeCheck || xray.routeCheck.via === "" ? root.errorColor
                   : xray.routeCheck.via === "block" ? root.errorColor : root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
            }

            RowLayout {
              width: parent.width
              spacing: Style.space(8)
              RowLabel { text: "Send to" }
            ChipGroup {
              options: root.ruleTargets
              value: root.ruleTarget
              cursorIndex: root.cursorRow === "ruleadd" ? root.chipIndex : -1
              Accessible.role: Accessible.Grouping
              Accessible.name: "New rule target: " + root.ruleTargetLabel(root.ruleTarget)
              Accessible.description: "Options: direct, VPN, block. h and l switch, Enter types the rule"
              Accessible.focusable: true
              Accessible.focused: cursorIndex >= 0
              onChanged: function(v) { root.ruleTarget = v; ruleField.forceActiveFocus() }
              onHovered: function(i, h) { if (h) root.cursorActive = false }
            }
              Item { Layout.fillWidth: true }
            }

            RowLayout {
              width: parent.width
              spacing: Style.space(8)
              RowLabel { text: "Match" }
            RowField {
              id: ruleField
              Layout.fillWidth: true
              icon: "󰐕"
              Accessible.name: "New rule, " + root.ruleTargetLabel(root.ruleTarget)
              placeholderText: "domain, IP/CIDR or geosite:…"
              maximumLength: 253
              Keys.onPressed: function(event) {
                if (event.key === Qt.Key_Escape) {
                  text = ""
                  keyCatcher.forceActiveFocus()
                  event.accepted = true
                } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                  if (root.addRule(text)) text = ""
                  event.accepted = true
                }
              }
            }
            }

            Repeater {
              model: xray.rules
              delegate: RowLayout {
                required property var modelData
                required property int index
                width: parent ? parent.width : 0
                spacing: Style.space(8)

                RowLabel {
                  text: root.ruleTargetLabel(modelData.target)
                  color: modelData.target === "block" ? root.errorColor : root.dim
                }

                Text {
                  textFormat: Text.PlainText
                  Layout.fillWidth: true
                  text: modelData.value
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  elide: Text.ElideMiddle
                }

                TextActionButton {
                  label: "󰅖"
                  a11yName: "Remove rule " + modelData.value
                  tooltip: "Remove this rule"
                  enabled: !xray.busy
                  hasCursor: root.cursorRule === index
                  onClicked: root.removeRule(index)
                }
              }
            }

            Text {
              textFormat: Text.PlainText
              visible: xray.rules.length === 0
              width: parent.width
              leftPadding: root.settingLabelWidth + Style.space(8)
              text: "Checked before Route and Adblock."
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              wrapMode: Text.WordWrap
            }
          }

          PanelSeparator { visible: xray.reachable && !root.firstRun && !root.settingsOpen; foreground: root.foreground }
          Column {
            visible: xray.reachable && !root.settingsOpen
            width: parent.width
            spacing: Style.space(6)

            RowLayout {
              visible: !root.firstRun
              width: parent.width
              spacing: Style.space(6)

              PanelSectionHeader {
                Layout.fillWidth: true
                text: "NODES"
                foreground: root.foreground
                fontFamily: root.fontFamily
              }

              TextActionButton {
                label: root.sortByLatency ? "󰒿 PING" : "󰒿 LIST"
                a11yName: "Order: " + (root.sortByLatency ? "fastest first" : "as in the subscription")
                tooltip: root.sortByLatency ? "Fastest first · click: subscription order" : "Subscription order · click: fastest first"
                onClicked: root.persistSetting("sortByLatency", !root.sortByLatency)
              }

              TextActionButton {
                label: xray.testing ? "Stop · " + root.elapsedText : root.failCount > 0 ? "Test · Fail " + root.failCount : "Test"
                tooltip: xray.testing ? "Stop the latency test, finished results are kept (Ctrl+T)"
                         : (root.filterQuery !== "" ? "Latency-test the filtered nodes" : "Latency-test all nodes")
                           + (root.visibleNodes.length > 200 ? " (the first 200)" : "")
                           + ". Ctrl+T tests the node under the cursor, or all; right-click tests one"
                enabled: xray.testing || (root.visibleNodes.length > 0 && !xray.busy)
                onClicked: xray.testNodes(root.visibleNodes)
              }
            }

            // Ctrl+S on a node: its QR for a phone, the link into the clipboard.
            ColumnLayout {
              visible: !!xray.share
              width: parent.width
              spacing: Style.space(4)

              RowLayout {
                Layout.fillWidth: true
                spacing: Style.space(6)
                PanelSectionHeader {
                  Layout.fillWidth: true
                  text: xray.share ? "SHARE · " + xray.share.name : ""
                  elide: Text.ElideRight
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                }
                TextActionButton {
                  label: "Copy link"
                  tooltip: xray.share && xray.share.kind === "json" ? "Copy its Xray JSON (no share link for this one)"
                                                                    : "Copy the link: it carries the credentials"
                  onClicked: if (xray.share) xray.shareNode({ key: xray.share.key, name: xray.share.name }, "copy")
                }
                TextActionButton {
                  label: "󰅖"
                  a11yName: "Close share"
                  tooltip: "Close (Ctrl+S)"
                  onClicked: xray.share = null
                }
              }

              Image {
                Layout.alignment: Qt.AlignHCenter
                visible: !!xray.share && xray.share.png !== ""
                // the stamp makes a new QR load over the same file name
                source: xray.share && xray.share.png ? "file://" + xray.share.png + "?" + xray.share.stamp : ""
                cache: false
                smooth: false
                fillMode: Image.PreserveAspectFit
                Layout.preferredWidth: Math.min(parent.width, Style.space(220))
                Layout.preferredHeight: Layout.preferredWidth
                Accessible.name: "QR code for " + (xray.share ? xray.share.name : "")
              }
            }

            Text {
              textFormat: Text.PlainText
              visible: xray.skippedText !== ""
              width: parent.width
              text: xray.skippedText
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              wrapMode: Text.WordWrap
            }

            RowLayout {
              visible: !root.firstRun
              width: parent.width
              spacing: Style.space(6)

              RowField {
                id: searchField
                icon: "󰍉"
                Accessible.name: "Filter nodes"
                Layout.fillWidth: true
                foreground: root.foreground
                placeholderText: "Filter nodes: just start typing"
                text: root.filterQuery
                onTextChanged: {
                  root.filterQuery = text
                  root.nodeIndex = 0
                  root.cursorActive = text !== ""
                }
                Keys.onPressed: function(event) {
                  // Ctrl+T tests the filtered nodes; every other chord keeps
                  // its text-editing meaning in the field
                  if ((event.modifiers & Qt.ControlModifier) && (event.key === Qt.Key_T || event.key === Qt.Key_C) && selectedText === "") {
                    root.runCtrl(event.key === Qt.Key_T ? "t" : "c")
                    event.accepted = true
                    return
                  }
                  // Esc clears and hands the keys back to the list (a second
                  // Esc there closes); Enter selects and does the same
                  if (event.key === Qt.Key_Escape) {
                    text = ""
                    keyCatcher.forceActiveFocus()
                    event.accepted = true
                    return
                  }
                  if (event.key === Qt.Key_Down || event.key === Qt.Key_Up) {
                    if (!root.cursorActive) root.cursorActive = true      // show it on the first node
                    else root.moveNodeCursor(event.key === Qt.Key_Down ? 1 : -1)
                    event.accepted = true
                    return
                  }
                  if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                    root.activateCursor()
                    keyCatcher.forceActiveFocus()
                    event.accepted = true
                  }
                }
              }

              TextActionButton {
                label: "󰅖"
                a11yName: "Clear filter"
                tooltip: "Clear filter"
                visible: root.filterQuery !== ""
                onClicked: { root.filterQuery = ""; searchField.text = ""; keyCatcher.forceActiveFocus() }
              }
            }

            Text {
              textFormat: Text.PlainText
              visible: root.visibleNodes.length === 0
              width: parent.width
              text: xray.touch === null ? "Checking…"
                    : root.filterQuery !== "" ? "No nodes match “" + root.filterQuery + "” — Esc clears the filter"
                    : root.firstRun ? "Paste the subscription link from your VPN provider below.\nA single server link (vless://, ss://…) or Xray JSON works too."
                    : "No nodes yet — add a subscription, a link or Xray JSON below."
              wrapMode: Text.WordWrap
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              horizontalAlignment: Text.AlignHCenter
            }
          }

        }

        delegate: Column {
          id: rowCol
          required property int index
          readonly property string groupTitle: root.visibleRows[index] ? root.visibleRows[index].title : ""
          width: nodeList.width
          spacing: Style.space(4)
          topPadding: groupTitle !== "" && index > 0 ? Style.space(6) : 0

          readonly property var head: root.visibleRows[index] ? root.visibleRows[index].head : null

          // Title, then traffic; time left on the right edge. A part running
          // low (or a failed update) turns dim red.
          Item {
            visible: rowCol.groupTitle !== ""
            width: parent.width
            height: groupTitleText.implicitHeight

            PanelSectionHeader {
              id: groupTitleText
              anchors.left: parent.left
              text: rowCol.groupTitle
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            PanelSectionHeader {
              anchors.left: groupTitleText.right
              anchors.right: groupExpiryText.left
              anchors.rightMargin: groupExpiryText.text !== "" ? Style.space(8) : 0
              elide: Text.ElideRight
              text: rowCol.head && rowCol.head.status !== "" ? "  ·  " + rowCol.head.status : ""
              foreground: rowCol.head && rowCol.head.low.usage ? root.errorColor : root.foreground
              fontFamily: root.fontFamily
            }

            PanelSectionHeader {
              id: groupExpiryText
              anchors.right: parent.right
              text: rowCol.head ? rowCol.head.expiry : ""
              foreground: rowCol.head && rowCol.head.low.expiry ? root.errorColor : root.foreground
              fontFamily: root.fontFamily
            }
          }

          NodeRow { globalIndex: rowCol.index }
        }

        footer: Column {
          property alias subUrl: subUrlField
          visible: !root.settingsOpen
          height: visible ? implicitHeight : 0
          width: nodeList.width
          spacing: Style.space(8)
          topPadding: Style.space(8)

          PanelSeparator { visible: xray.reachable; foreground: root.foreground }

          Column {
            visible: xray.reachable
            width: parent.width
            spacing: Style.space(6)

            RowLayout {
              width: parent.width
              spacing: Style.space(6)

              PanelSectionHeader {
                text: "SUBSCRIPTIONS"
                Layout.alignment: Qt.AlignVCenter
                foreground: root.foreground
                fontFamily: root.fontFamily
              }

              // the count is the expander, drawn like the SETTINGS summary so
              // it reacts to the pointer the same way
              TextActionButton {
                visible: xray.subs.length > 0
                label: xray.subs.length + (root.subsShown ? "  󰅃" : "  󰅀")
                a11yName: (root.subsShown ? "Collapse" : "Expand") + " subscriptions, " + xray.subs.length
                tooltip: root.subsShown ? "Hide the subscriptions" : "Show the subscriptions"
                onClicked: root.subsOpen = !root.subsOpen
              }

              Item { Layout.fillWidth: true }

              TextActionButton {
                visible: xray.subs.length > 0
                label: xray.updating ? "Updating…" : root.subFailCount > 0 ? "Update all · Fail " + root.subFailCount : "Update all"
                tooltip: "Download every subscription again (Ctrl+R)"
                enabled: !xray.busy
                hasCursor: root.cursorRow === "subs"
                onClicked: xray.updateSubscriptions()
              }
            }

            RowLayout {
              visible: root.subsShown
              width: parent.width
              spacing: Style.space(6)

              RowField {
                id: subUrlField
                icon: "󰌹"
                Accessible.name: "Subscription URL, server link or Xray JSON"
                Layout.fillWidth: true
                foreground: root.foreground
                placeholderText: "Sub URL, vless:// link or Xray JSON"
                onAccepted: if (text.trim() !== "") root.importSub()
                onTextChanged: if (!xray.importing) xray.importNote = ""
                Keys.onEscapePressed: function(event) {
                  if (text !== "") text = ""
                  else keyCatcher.forceActiveFocus()
                  event.accepted = true
                }
              }

              TextActionButton {
                label: "Add"
                enabled: !xray.busy                  // empty field: Add puts the cursor there
                onClicked: if (subUrlField.text.trim() === "") subUrlField.forceActiveFocus(); else root.importSub()
              }

              TextActionButton {
                label: "󰐲 QR"
                a11yName: "Scan a QR code on screen"
                tooltip: "Drag a box around a QR code on screen: a subscription or a server"
                enabled: !xray.busy
                onClicked: xray.scanQr()
              }
            }

            Text {
              textFormat: Text.PlainText
              visible: root.subsShown && xray.importNote !== ""
              width: parent.width
              text: xray.importNote
              onTextChanged: function() { if (text !== "") Accessible.announce(text) }
              color: xray.importing ? root.dim : root.errorColor
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              wrapMode: Text.WordWrap
            }

            Column {
              visible: root.subsShown
              width: parent.width
              spacing: Style.space(4)

            Repeater {
              model: xray.subs.length
              delegate: CursorSurface {
                id: subRow
                required property int index
                readonly property var sub: xray.subs[index]
                width: parent.width
                implicitHeight: subInner.implicitHeight + Style.spacing.rowPaddingX
                foreground: root.foreground
                fill: root.hoverFill

                RowLayout {
                  id: subInner
                  anchors.left: parent.left
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  anchors.leftMargin: Style.space(8)
                  anchors.rightMargin: Style.space(8)
                  spacing: Style.space(8)

                  Text {
                    textFormat: Text.PlainText
                    text: "󰌹"
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                  }

                  ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Style.space(1)

                    Text {
                      textFormat: Text.PlainText
                      Layout.fillWidth: true
                      text: subRow.sub ? (subRow.sub.title || subRow.sub.host) : ""
                      color: root.foreground
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.body
                      elide: Text.ElideRight
                    }

                    Text {
                      textFormat: Text.PlainText
                      Layout.fillWidth: true
                      visible: text !== ""
                      text: subRow.sub ? (subRow.sub.error ? "󰀦 " + subRow.sub.error : Model.subInfoLabel(subRow.sub.info)) : ""
                      color: subRow.sub && (subRow.sub.error || Model.subLow(subRow.sub.info).usage
                             || Model.subLow(subRow.sub.info).expiry) ? root.errorColor : root.dim
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.bodySmall
                      elide: Text.ElideRight
                    }
                  }

                  TextActionButton {
                    visible: !!subRow.sub && !subRow.sub.local            // Manual: nothing to download
                    label: "Update"
                    a11yName: "Update " + (subRow.sub ? subRow.sub.title || subRow.sub.host : "")
                    tooltip: "Download this subscription again"
                    enabled: !xray.busy
                    hasCursor: root.cursorSub === subRow.index && root.chipIndex === 0
                    onClicked: if (subRow.sub) xray.updateSub(subRow.sub.index)
                  }

                  TextActionButton {
                    id: removeButton
                    readonly property bool armed: !!subRow.sub && root.armedSub === root.subKey(subRow.sub)
                    // same width armed or not, so "Update" never shifts
                    Layout.preferredWidth: Math.ceil(confirmMetrics.advanceWidth) + 2 * Style.spacing.controlPaddingX
                    label: armed ? "Confirm" : "Remove"
                    a11yName: (armed ? "Confirm removing " : "Remove ") + (subRow.sub ? subRow.sub.title || subRow.sub.host : "")
                    onArmedChanged: if (armed) Accessible.announce("Press again to remove " + (subRow.sub ? subRow.sub.title || subRow.sub.host : ""))
                    // armed reads as a state, not only as a different word
                    bordered: armed
                    selected: armed
                    tint: armed ? root.errorColor : root.foreground
                    tooltip: armed ? "Click again to remove " + (subRow.sub ? subRow.sub.title || subRow.sub.host : "") + " and its nodes"
                                   : subRow.sub && subRow.sub.local ? "Remove every server added by hand"
                                   : "Remove this subscription and its nodes"
                    enabled: !xray.busy
                    hasCursor: root.cursorSub === subRow.index && root.chipIndex === (subRow.sub && subRow.sub.local ? 0 : 1)
                    onClicked: root.armRemove(subRow.index)
                  }
                }
              }
            }
            }
          }
        }
      }
    }
  }

  // Text input shaped like a list row: the same height, no box at rest (hover
  // and focus use the kit's control states), and an icon in the row's
  // leading glyph column so typed text starts where node/subscription names do.
  component RowField: TextField {
    id: rowField
    property string icon: ""
    readonly property bool _hotState: hovered || activeFocus
    foreground: root.foreground
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
    implicitHeight: root.ctlHeight
    topPadding: 0
    bottomPadding: 0
    verticalAlignment: TextInput.AlignVCenter
    leftPadding: root.rowTextInset
    rightPadding: Style.space(8)
    background: BorderSurface {
      radius: Style.cornerRadius
      color: rowField.activeFocus ? Style.focusFillFor(root.foreground, Color.accent)
           : rowField.hovered ? Style.hoverFillFor(root.foreground, Color.accent) : "transparent"
      borderSpec: rowField.activeFocus ? Border.controlSpec("focus", root.foreground, Color.accent)
                : rowField.hovered ? Border.controlSpec("hover-cursor", root.foreground, Color.accent)
                : Border.none()

      Text {
        textFormat: Text.PlainText
        anchors.left: parent.left
        anchors.leftMargin: Style.space(8)
        anchors.verticalCenter: parent.verticalCenter
        width: root.rowGlyphWidth
        horizontalAlignment: Text.AlignHCenter
        text: rowField.icon
        color: rowField._hotState ? root.foreground : root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }
    }
  }

  // Text action on the kit's Button (hover, cursor, tooltip), plus a tint
  // for destructive confirmation and a dimmed disabled state.
  // The kit's ButtonGroup with the panel's control height (the kit gives no
  // way to set its chips' padding).
  component ChipGroup: Row {
    id: chips
    property var options: []
    property string value: ""
    property int cursorIndex: -1
    property color foreground: root.foreground
    property string fontFamily: root.fontFamily
    property real fontSize: Style.font.caption
    signal changed(string v)
    signal hovered(int i, bool h)
    spacing: Style.space(4)
    Repeater {
      model: chips.options
      delegate: Button {
        required property var modelData
        required property int index
        text: modelData.label
        tooltipText: modelData.tooltip || ""
        selected: modelData.value === chips.value
        hasCursor: chips.cursorIndex === index
        bordered: true
        implicitHeight: root.ctlHeight
        foreground: chips.foreground
        fontFamily: chips.fontFamily
        fontSize: chips.fontSize
        onClicked: chips.changed(modelData.value)
        onHovered: function(h) { chips.hovered(index, h) }
      }
    }
  }

  // A settings row: label, switch, and a note that toggles too (a small
  // switch is a small target). `usable` false greys it and blocks clicks.
  // One Xray freedom.fragment parameter, shown only while fragmentation is on.
  // One Xray freedom.fragment parameter; Enter applies all three.
  component FragField: RowField {
    id: ff
    property string key: ""
    property string hint: ""
    property int col: 0
    Layout.fillWidth: true
    leftPadding: Style.space(6)
    text: xray.fragmentOpts[ff.key] || ""
    placeholderText: ff.hint
    maximumLength: 16
    Accessible.name: "Fragmentation " + ff.key
    // the kit field shows no cursor ring: a hovered border marks the keyboard spot
    background: BorderSurface {
      radius: Style.cornerRadius
      color: ff.activeFocus ? Style.focusFillFor(root.foreground, Color.accent) : "transparent"
      borderSpec: ff.activeFocus ? Border.controlSpec("focus", root.foreground, Color.accent)
                : ff.hovered || (root.cursorRow === "fragopts" && root.chipIndex === ff.col)
                  ? Border.controlSpec("hover-cursor", root.foreground, Color.accent)
                  : Border.controlSpec("normal", root.foreground, Color.accent)
    }
    Keys.onPressed: function(event) {
      if (event.key === Qt.Key_Escape) {
        text = xray.fragmentOpts[ff.key] || ""
        keyCatcher.forceActiveFocus()
        event.accepted = true
      } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
        root.applyFragmentOpts()
        keyCatcher.forceActiveFocus()
        event.accepted = true
      }
    }
  }

  // Several on/off switches as one row of pills: lit = on.
  component PillRow: Flow {
    id: pr
    property var options: []
    property string row: ""
    width: parent ? parent.width : 0
    spacing: Style.space(4)
    Repeater {
      model: pr.options
      delegate: Button {
        required property var modelData
        required property int index
        text: (modelData.on ? "󰄬 " : "") + modelData.label
        tooltipText: modelData.tooltip
        selected: modelData.on
        bordered: true
        hasCursor: root.cursorRow === pr.row && root.chipIndex === index
        opacity: modelData.usable && !xray.busy ? 1.0 : 0.45
        foreground: root.foreground
        fontFamily: root.fontFamily
        fontSize: Style.font.caption
        implicitHeight: root.ctlHeight
        Accessible.role: Accessible.CheckBox
        Accessible.name: modelData.label
        Accessible.checked: modelData.on
        Accessible.description: modelData.tooltip
        Accessible.focusable: true
        Accessible.focused: hasCursor
        onClicked: if (modelData.usable) root.flipPill(modelData.key)
        onHovered: function(h) { if (h) root.cursorActive = false }
      }
    }
  }

  // Label + chips; the cursor walks the chips when its row is current.
  component ChipRow: RowLayout {
    id: cr
    property string label: ""
    property var options: []
    property string value: ""
    property string row: ""
    property string trailing: ""         // a result beside the chips (speed, geo source)
    property bool sub: false             // a parameter of the row above: indented label
    signal changed(string v)
    width: parent ? parent.width : 0
    spacing: Style.space(8)
    RowLabel { text: cr.label; leftPadding: cr.sub ? Style.space(10) : 0 }
    ChipGroup {
      options: cr.options
      value: cr.value
      cursorIndex: root.cursorRow === cr.row ? root.chipIndex : -1
      opacity: xray.busy ? 0.45 : 1.0
      Accessible.role: Accessible.Grouping
      Accessible.name: cr.label + ": " + cr.value
      Accessible.focusable: true
      Accessible.focused: cursorIndex >= 0
      onChanged: function(v) { cr.changed(v) }
      onHovered: function(i, h) { if (h) root.cursorActive = false }
    }
    Text {
      visible: cr.trailing !== ""
      textFormat: Text.PlainText
      text: cr.trailing
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
    }
    Item { Layout.fillWidth: true }
  }

  // Label + one text field: Enter submits, Esc restores the saved value.
  component FieldRow: RowLayout {
    id: fw
    property string label: ""
    property string value: ""
    property string hint: ""
    property string icon: ""
    property string row: ""
    property alias field: fwField
    property bool sub: false             // a parameter of the row above: indented label
    signal submitted(string text)
    width: parent ? parent.width : 0
    spacing: Style.space(8)
    RowLabel { text: fw.label; leftPadding: fw.sub ? Style.space(10) : 0 }
    RowField {
      id: fwField
      Layout.fillWidth: true
      icon: fw.icon
      leftPadding: fw.icon !== "" ? root.rowTextInset : Style.space(8)
      text: fw.value
      placeholderText: fw.hint
      maximumLength: 128
      Accessible.name: fw.label + ", " + fw.hint
      Keys.onPressed: function(event) {
        if (event.key === Qt.Key_Escape) {
          text = fw.value
          keyCatcher.forceActiveFocus()
          event.accepted = true
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
          fw.submitted(text.trim())
          keyCatcher.forceActiveFocus()
          event.accepted = true
        }
      }
    }
  }

  // Group title: more space above than below, optional quiet trailing note.
  // A group title; every group after the first opens with a hairline.
  component SectionTitle: Column {
    id: sct
    property string text: ""
    property string trailing: ""
    property bool first: false
    width: parent ? parent.width : 0
    topPadding: sct.first ? 0 : Style.space(6)
    spacing: Style.space(6)
    PanelSeparator { visible: !sct.first; width: parent.width; foreground: root.foreground }
    RowLayout {
      width: parent.width
      spacing: Style.space(8)
      PanelSectionHeader {
        Layout.fillWidth: true
        topPadding: sct.first ? Math.ceil(fontSize * 0.15) : 0
        text: sct.text
        foreground: root.foreground
        fontFamily: root.fontFamily
      }
      Text {
        textFormat: Text.PlainText
        visible: sct.trailing !== ""
        Layout.alignment: Qt.AlignBottom
        text: sct.trailing
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }
    }
  }

  // Quiet row label inside a group: the group title is the loud one.
  component RowLabel: Text {
    textFormat: Text.PlainText
    Layout.preferredWidth: root.settingLabelWidth
    Layout.alignment: Qt.AlignVCenter
    color: root.dim
    font.family: root.fontFamily
    font.pixelSize: Style.font.bodySmall
    elide: Text.ElideRight
  }

  // A settings row: label, then the switch at the right edge. What it does
  // is the tooltip (and the keyboard hint); only a reason it cannot be used
  // shows inline, wrapped, so it never runs off the panel.
  component SettingToggle: ColumnLayout {
    id: st
    property string label: ""
    property string a11yName: ""
    property string note: ""
    property bool checked: false
    property bool usable: true
    property bool busy: false              // dimmed like the chips; the click still says why
    property bool hasCursor: false
    signal flip()
    width: parent ? parent.width : 0
    spacing: Style.space(2)
    RowLayout {
      Layout.fillWidth: true
      spacing: Style.space(8)
      RowLabel {
        id: stLabel
        text: st.label
        color: stHover.containsMouse ? root.foreground : root.dim
        MouseArea {
          id: stHover
          anchors.fill: parent
          anchors.topMargin: -Style.space(6)
          anchors.bottomMargin: -Style.space(6)
          hoverEnabled: true
          enabled: st.usable
          cursorShape: Qt.PointingHandCursor
          onClicked: st.flip()
          onEntered: root.cursorActive = false
        }
        PanelToolTip {
          visible: stHover.containsMouse && st.note !== ""
          text: st.note
          fontFamily: root.fontFamily
        }
      }
      ToggleSwitch {
        trackHeight: Math.round(Style.font.caption * 1.2)
        cursorPad: Style.space(3)
        Layout.alignment: Qt.AlignVCenter
        checked: st.checked
        hasCursor: st.hasCursor
        opacity: st.usable && !st.busy ? 1.0 : 0.45
        foreground: root.foreground
        onToggled: if (st.usable) st.flip()
        onHovered: function(h) { if (h) root.cursorActive = false }
        Accessible.role: Accessible.CheckBox
        Accessible.name: st.a11yName
        Accessible.description: st.note
        Accessible.checked: st.checked
        Accessible.focusable: true
        Accessible.focused: hasCursor
      }
      Item { Layout.fillWidth: true }
    }
    Text {
      textFormat: Text.PlainText
      visible: !st.usable && st.note !== ""
      Layout.fillWidth: true
      leftPadding: root.settingLabelWidth + Style.space(8)
      text: st.note
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
      wrapMode: Text.WordWrap
    }
  }

  component TextActionButton: Button {
    property string label: ""
    property string a11yName: ""               // when the label alone is ambiguous
    property string tooltip: ""
    property color tint: root.foreground
    text: label
    tooltipText: tooltip
    foreground: enabled ? tint : root.dim
    fontFamily: root.fontFamily
    fontSize: Style.font.caption
    implicitHeight: root.ctlHeight
    onHovered: function(h) { if (h) root.cursorActive = false }
    Accessible.role: Accessible.Button
    Accessible.name: a11yName !== "" ? a11yName : label
    Accessible.description: tooltip
    Accessible.focusable: true
    Accessible.focused: hasCursor
    Accessible.onPressAction: if (enabled) clicked()
  }

  // A small clickable glyph inside a node row (above the row's own MouseArea).
  component NodeIcon: Text {
    id: ni
    property string icon: ""
    property bool lit: false
    property string tip: ""
    signal clicked()
    textFormat: Text.PlainText
    text: icon
    color: lit || niMouse.containsMouse ? root.foreground : root.dim
    font.family: root.fontFamily
    font.pixelSize: Style.font.bodySmall
    Layout.alignment: Qt.AlignVCenter
    Accessible.role: Accessible.Button
    Accessible.name: tip
    Accessible.onPressAction: ni.clicked()
    MouseArea {
      id: niMouse
      anchors.fill: parent
      anchors.margins: -Style.space(3)        // a target bigger than the glyph
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: ni.clicked()
    }
    PanelToolTip { visible: niMouse.containsMouse; text: ni.tip; fontFamily: root.fontFamily }
  }

  component NodeRow: CursorSurface {
    id: nodeRow
    property int globalIndex: 0
    readonly property var node: {
      // Index into the already-flattened cursor list (same order the cursor walks).
      var flat = root.visibleNodes
      return globalIndex < flat.length ? flat[globalIndex] : null
    }
    // !! and not !== null: a row being removed briefly sees undefined
    readonly property bool isConnected: !!node && node.connected === true
    readonly property string latencyText: node ? Model.latencyLabel(node.latency) : ""
    readonly property bool latencyBadLat: node ? Model.latencyBad(latencyText) : false
    // Auto's "address" is its member count; other rows keep transport in the tooltip.
    readonly property string meta: !node || node.key !== "auto" ? "" : node.address
    readonly property bool fastest: !!node && node.key === root.fastestKey
    // off: the node the switch will use lights up too
    readonly property bool isChosen: !!node && !xray.connected && !!xray.connectTarget && node.key === xray.connectTarget.key

    hasCursor: root.cursorActive && root.nodeIndex === globalIndex
    current: isConnected
    foreground: root.foreground
    fill: root.hoverFill
    currentFill: root.selectedFill
    width: parent ? parent.width : 0
    implicitHeight: rowInner.implicitHeight + Style.spacing.rowPaddingX
    Accessible.role: Accessible.Button
    Accessible.name: node ? node.name + (isConnected ? ", connected" : isChosen ? ", selected" : "") + (latencyText !== "" ? ", " + latencyText : "")
                            + (fastest ? ", fastest" : "") : ""
    // the panel's own cursor is the focus a screen reader should follow
    Accessible.focusable: true
    Accessible.focused: hasCursor
    Accessible.onPressAction: if (node) xray.selectNode(node)

    MouseArea {
      id: nodeMouse
      anchors.fill: parent
      acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onPositionChanged: function(mouse) {
        if (pointerGate.moved(nodeMouse, mouse)) root.setNodeCursor(nodeRow.globalIndex)
      }
      onClicked: function(mouse) {
        if (!nodeRow.node) return
        if (mouse.button === Qt.MiddleButton) xray.toggleFav(nodeRow.node)
        else if (mouse.button === Qt.RightButton) xray.testNodes([nodeRow.node])
        else xray.selectNode(nodeRow.node)
      }
    }

    RowLayout {
      id: rowInner
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(8)
      anchors.rightMargin: Style.space(8)
      spacing: Style.space(8)

      Text {
        textFormat: Text.PlainText
        text: nodeRow.isConnected || nodeRow.isChosen ? "󰐾" : "󰐽"
        Accessible.ignored: true                  // the row's name says "connected"
        color: nodeRow.isConnected ? root.foreground : root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        Layout.alignment: Qt.AlignVCenter
      }

      Text {
        textFormat: Text.PlainText
        Layout.fillWidth: true
        id: nodeName
        text: nodeRow.node ? nodeRow.node.name : ""
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        font.bold: nodeRow.isConnected
        elide: Text.ElideRight
      }

      // Per-node actions: speed test, star. Dim until hovered or set.
      NodeIcon {
        visible: !!nodeRow.node && nodeRow.node.key !== "auto"
        icon: "󰓅"
        lit: xray.speedTesting && xray.speedKey === (nodeRow.node ? nodeRow.node.key : "")
        tip: lit ? "Measuring… click to stop" : "Speed test, this node on its own (up to 25 MB)"
        onClicked: {
          if (xray.speedTesting) xray.stopSpeed()
          else root.guarded(function() { xray.speedTest(nodeRow.node) })
        }
      }

      NodeIcon {
        visible: !!nodeRow.node && nodeRow.node.key !== "auto"
        icon: nodeRow.node && nodeRow.node.fav ? "★" : "☆"
        lit: !!nodeRow.node && nodeRow.node.fav
        tip: lit ? "Unstar" : "Star: sorts first, Auto can use only starred"
        onClicked: xray.toggleFav(nodeRow.node)
      }

      Text {
        textFormat: Text.PlainText
        visible: nodeRow.meta !== ""
        text: nodeRow.meta
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        elide: Text.ElideLeft
        Layout.alignment: Qt.AlignVCenter
      }

      // Fixed, right-aligned cell: ping, the speed under it; results line up
      // and never shift the name. Two short lines fit the row's height.
      Column {
        visible: !!nodeRow.node && nodeRow.node.key !== "auto"
        readonly property bool two: !!nodeRow.node && nodeRow.node.speed > 0
        Layout.preferredWidth: root.latencyCellWidth
        // never taller than the name: a speed line must not grow the row
        Layout.preferredHeight: nodeName.implicitHeight
        Layout.alignment: Qt.AlignVCenter
        spacing: -Style.space(3)
        topPadding: two ? -Style.space(3) : (nodeName.implicitHeight - children[0].implicitHeight) / 2
        Text {
          textFormat: Text.PlainText
          width: parent.width
          horizontalAlignment: Text.AlignRight
          text: (nodeRow.fastest ? "󰉁 " : "") + nodeRow.latencyText
          Accessible.ignored: true
          color: nodeRow.latencyBadLat ? root.dim : root.foreground      // "timeout" says it; don't shout
          font.family: root.fontFamily
          font.pixelSize: parent.two ? Style.font.caption : Style.font.bodySmall      // the number nodes are chosen by
          font.bold: nodeRow.fastest
        }
        Text {
          textFormat: Text.PlainText
          visible: !!nodeRow.node && nodeRow.node.speed > 0
          width: parent.width
          horizontalAlignment: Text.AlignRight
          text: nodeRow.node ? "󰓅 " + Model.mbpsLabel(nodeRow.node.speed) : ""
          Accessible.ignored: true
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }
      }
    }

    PanelToolTip {
      visible: nodeMouse.containsMouse && !!nodeRow.node
      text: (nodeRow.node && nodeRow.node.key !== "auto" && nodeRow.node.address
               ? nodeRow.node.address + (nodeRow.node.net ? " · " + nodeRow.node.net : "") + (nodeRow.fastest ? " · fastest" : "") + "\n" : "")
            + (nodeRow.isConnected ? "Connected · right-click to test latency" : xray.connected ? "Click to switch · right-click to test latency" : "Click to select · right-click to test latency")
            + (nodeRow.node && nodeRow.node.key !== "auto" ? "\nMiddle-click: " + (nodeRow.node.fav ? "unstar" : "star") + " · Ctrl+S: share" : "")
      fontFamily: root.fontFamily
    }
  }
}
