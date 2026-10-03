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
  readonly property real settingLabelWidth: Style.space(52)
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
    if (v === "global") { if (xray.region) xray.setRouting("global") }
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
      : !settingsOpen ? ["hero", "settings"]
      : regionsOpen ? ["hero", "settings", "mode", "route", "regions", "ads"] : ["hero", "settings", "mode", "route", "ads"]
  readonly property string settingsSummary: (xray.mode === "tun" ? "TUN" : "PROXY")
      + " · " + (xray.region ? xray.region.code.toUpperCase() + " DIRECT" : "ALL")
      + (xray.adblock ? " · ADBLOCK" : "")
  function toggleSettings() {
    var onRow = cursorRow === "settings"
    if (settingsOpen) regionsOpen = false
    settingsOpen = !settingsOpen
    if (onRow) nodeIndex = settingRows.indexOf("settings") - settingRows.length
  }
  readonly property int footerRows: xray.reachable ? 1 + (subsShown ? xray.subs.length : 0) : 0
  property int chipIndex: 0
  readonly property string cursorRow: !cursorActive ? ""
      : nodeIndex < 0 ? (settingRows[settingRows.length + nodeIndex] || "")
      : nodeIndex < visibleNodes.length ? "node"
      // a filter that matches nothing leaves the cursor nowhere: Enter must
      // not fall through to the Config button below the list
      : visibleNodes.length === 0 && filterQuery !== "" ? ""
      : nodeIndex === visibleNodes.length ? "subs" : "sub"
  readonly property int cursorSub: cursorRow === "sub" ? nodeIndex - visibleNodes.length - 1 : -1
  // The country chip only changes DIRECT's country; hidden while ALL is on.
  // One copy of what each chip does: its tooltip and the keyboard hint line
  // (kept short enough for that single line).
  readonly property var modeOptions: [
    { value: "proxy", label: "PROXY", tooltip: "Apps that use the system proxy go through the VPN" },
    { value: "tun", label: "TUN", tooltip: xray.tunInstalled ? "All system traffic goes through the VPN"
                                                            : "All traffic via the VPN · first switch asks your password" }
  ]
  readonly property var routeOptions: [
    { value: "global", label: "ALL", tooltip: "Everything through the VPN, except your local network" },
    { value: "direct", label: routeRegion ? routeRegion.code.toUpperCase() + " DIRECT" : "DIRECT",
      tooltip: routeRegion ? routeRegion.name + " sites go direct, the rest via the VPN"
                           : "One country's sites go direct, not through the VPN" }
  ]

  function chipCount(row) {
    return row === "mode" ? 2 : row === "route" ? 3
         : row === "regions" ? xray.regions.length
         : row === "subs" ? (xray.subs.length > 0 ? 2 : 1)
         : row === "sub" ? (xray.subs[cursorSub] && xray.subs[cursorSub].local ? 1 : 2) : 1
  }

  function currentChip(row) {
    if (row === "mode") return xray.mode === "tun" ? 1 : 0
    if (row === "route") return xray.region ? 1 : 0
    if (row !== "regions") return 0
    for (var i = 0; i < xray.regions.length; i++)
      if (xray.routing === xray.regions[i].code + "-direct") return i
    return 0
  }

  function moveChip(dx) {
    if (cursorRow === "") return
    pointerGate.reset()
    chipIndex = Math.max(0, Math.min(chipCount(cursorRow) - 1, chipIndex + dx))
  }

  function activateChip() {
    var r = cursorRow
    if (r === "hero") requestToggle()
    else if (r === "settings") toggleSettings()
    else if (r === "mode") chooseMode(chipIndex === 1 ? "tun" : "proxy")
    else if (r === "route") {
      if (chipIndex < 2) chooseRoute(chipIndex === 1 ? "direct" : "global")
      else regionsOpen = !regionsOpen
    }
    else if (r === "regions" && xray.regions[chipIndex]) pickRegion(xray.regions[chipIndex].code)
    else if (r === "ads") { if (xray.geo || xray.adblock) xray.setAdblock(!xray.adblock) }
    else if (r === "subs") { if (chipIndex === 0) xray.openWebUi(); else xray.updateSubscriptions() }
    else if (r === "sub" && xray.subs[cursorSub]) {
      // the Manual group has no Update: its only chip is Remove
      if (chipIndex === 0 && !xray.subs[cursorSub].local) xray.updateSub(xray.subs[cursorSub].index)
      else armRemove(cursorSub)
    }
  }

  // Removal can't be undone (the URL is a secret the user would have to find
  // again), so it takes a second press on the same spot within 4 s.
  property int armedSub: -1
  Timer { id: disarmTimer; interval: 4000; onTriggered: root.armedSub = -1 }
  function armRemove(i) {
    if (armedSub === i) { armedSub = -1; xray.subRemove(xray.subs[i].index); return }
    armedSub = i
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
  readonly property string lastNodeKey: settings ? String(settings.lastNodeKey || "") : ""

  // Off while the kill switch holds lets traffic out unprotected, so it takes
  // a second press within 4 s, like Remove. Every on/off path comes here.
  property bool killArmed: false
  Timer { id: killDisarm; interval: 4000; onTriggered: root.killArmed = false }
  onKillArmedChanged: if (killArmed) xray.flash("Kill switch is holding: press again to turn off, traffic would go direct")
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
  // there "on" is drawn in the brightest colour, the foreground; the shield's
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
  readonly property var visibleGroups: Model.filterNodes(xray.touch ? xray.touch.groups : [], filterQuery)
  readonly property var visibleRows: {
    var out = []
    for (var g = 0; g < visibleGroups.length; g++) {
      var grp = visibleGroups[g]
      var st = grp.status === undefined || grp.status === null ? "" : String(grp.status).trim()
      var title = grp.subscriptionId === "auto" ? ""          // one row needs no header
                : grp.title + (st === "" || st === "undefined" || st === "null" ? "" : "  ·  " + st)
      for (var i = 0; i < grp.nodes.length; i++) out.push({ node: grp.nodes[i], title: i === 0 ? title : "" })
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
      nodeList.positionViewAtBeginning()
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
      else xray.testNodes(root.visibleNodes)
    }
    else if (k === "l") xray.openLogs()
    else if (k === "r") xray.updateSubscriptions()             // Ctrl+U/W stay text editing
    else if (k === "o") xray.openWebUi()
    else if (k === "a") root.focusSubUrl()
    else if (k === "c") {
      // a toggle, as the switch and the bar's right-click
      if (!xray.toggleBusy) root.requestToggle()
    }
  }

  function startTypeAhead(t) {
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
    if (node) xray.connectNode(node)
  }

  property real nowMs: Date.now()
  Timer {
    interval: 1000
    repeat: true
    running: xray.testing && root.opened
    onTriggered: root.nowMs = Date.now()
  }
  readonly property string elapsedText: {
    var sec = Math.max(0, Math.floor((nowMs - xray.longStartedMs) / 1000))
    return Math.floor(sec / 60) + ":" + ("0" + sec % 60).slice(-2)
  }

  function focusSubUrl() {
    subsOpen = true
    Qt.callLater(function() {
      if (!nodeList.footerItem) return
      nodeList.positionViewAtEnd()
      nodeList.footerItem.subUrl.forceActiveFocus()
    })
  }

  readonly property string fastestKey: Model.fastestKey(visibleNodes)
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
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refreshNow(): string { xray.refresh(); return "ok" }
    function status(): string { return xray.heroSummary }
    function connect(): string { xray.toggleConnection(root.lastNodeKey); return "ok" }
    function disconnect(): string { xray.disconnect(); return "ok" }
    function toggleProxy(): string { xray.toggleConnection(root.lastNodeKey); return "ok" }
    function select(name: string): string {
      var q = String(name).toLowerCase()
      var nodes = xray.touch ? xray.touch.nodes : []
      for (var i = 0; i < nodes.length; i++) {
        if (nodes[i].name.toLowerCase().indexOf(q) !== -1) { xray.connectNode(nodes[i]); return "ok" }
      }
      return "no node matches: " + name
    }
    function test(): string { xray.testNodes(xray.touch ? xray.touch.nodes : []); return "ok" }
    function updateSubs(): string { xray.updateSubscriptions(); return "ok" }
    function startCore(): string { xray.startCore(); return "ok" }
    function stopCore(): string { xray.stopCore(); return "ok" }
    function subRemove(index: string): string { xray.subRemove(index); return "ok" }
    function mode(m: string): string { xray.setMode(m); return "ok" }
    function routing(p: string): string { xray.setRouting(p); return "ok" }
    function adblock(on: string): string { xray.setAdblock(on === "on" || on === "true"); return "ok" }
    function tunSetup(): string { xray.tunSetup(false); return "ok" }
    function webui(): string { xray.openWebUi(); return "ok" }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    dimmed: xray.reachable && !root.onTarget
    // an action started from the bar (right-click) reports back here too
    tooltipText: (xray.errorText !== "" ? "󰀦 " + xray.errorText + "\n" : "")
                 + (xray.pending !== "" ? xray.actionStatus
                    : xray.heroSummary + " · right-click to " + (xray.connected ? "disconnect" : "connect"))
    iconComponent: Component {
      Item {
        XrayIcon {
          anchors.centerIn: parent
          iconSize: Style.space(11)
          color: root.barIconColor
          filled: root.tunnelUp
          half: xray.mode !== "tun"   // proxy covers only some apps
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
    contentWidth: panel.fittedContentWidth(Style.space(400))
    contentHeight: panel.fittedContentHeight(pinned.height + Style.space(12) + nodeList.contentHeight,
                                             Style.space(620))

    PanelKeyCatcher {
      id: keyCatcher
      // Inline editors get every key (kit contract); they handle Up/Down/Enter/Esc themselves.
      blocked: (nodeList.headerItem !== null && nodeList.headerItem.search.activeFocus)
               || (nodeList.footerItem !== null && nodeList.footerItem.subUrl.activeFocus)
      anchors.fill: parent
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
        root.keysUsed = true
        var code = t.charCodeAt(0)
        if (code > 0 && code < 27) { root.runCtrl(String.fromCharCode(96 + code)); return }   // Ctrl+T = "\x14"
        if (t === "?") { root.legendHidden = !root.legendHidden; return }
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
        spacing: Style.space(12)

        PanelHero {
          id: hero
          width: parent.width
          title: xray.heroTitle
          meta: xray.heroState
          foreground: root.foreground
          fontFamily: root.fontFamily
          iconOpacity: root.onTarget ? 1.0 : 0.5
          iconComponent: Component {
            XrayIcon {
              iconSize: Style.font.display
              color: root.tunnelUp ? root.onColor : hero.foreground
              filled: root.tunnelUp
              half: xray.mode !== "tun"   // proxy covers only some apps
              warning: !xray.reachable || xray.errorText !== "" || xray.subsTrouble
              badgeColor: root.errorColor
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
                      : xray.connected ? "Disconnect (Ctrl+C)"
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
          readonly property string kind: xray.actionStatus !== "" ? "action"
                                       : xray.errorText !== "" ? "error"
                                       : root.firstRun || !xray.connected ? "none" : "traffic"
          visible: kind !== "none"
          width: parent.width
          spacing: Style.space(8)

          Text {
            textFormat: Text.PlainText
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            text: statusRow.kind === "action" ? xray.actionStatus
                  : statusRow.kind === "error" ? "󰀦 " + xray.errorText
                  : !statusRow.live ? "Measuring traffic…"
                  : "󰁅 " + Model.formatSpeed(xray.traffic.downSpeed)
                    + "   󰁝 " + Model.formatSpeed(xray.traffic.upSpeed)
                    + "   ·   Downloaded " + Model.formatBytes(xray.traffic.downTotal)
            color: statusRow.kind === "error" ? root.errorColor
                   : statusRow.kind === "traffic" && statusRow.live ? root.foreground : root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            wrapMode: statusRow.kind === "error" ? Text.WordWrap : Text.NoWrap
            elide: statusRow.kind === "error" ? Text.ElideNone : Text.ElideRight
            Accessible.role: Accessible.StaticText
            Accessible.name: statusRow.kind === "error" ? "Error: " + xray.errorText
                             : statusRow.kind === "action" ? xray.actionStatus
                             : statusRow.live ? "Download " + Model.formatSpeed(xray.traffic.downSpeed)
                                                + ", upload " + Model.formatSpeed(xray.traffic.upSpeed)
                             : "Measuring traffic"
            onTextChanged: if (statusRow.kind === "error"
                               || (statusRow.kind === "action" && !/^Testing \d/.test(xray.actionStatus)))
                             Accessible.announce(statusRow.kind === "error" ? "Error: " + xray.errorText : xray.actionStatus)
          }

          TextActionButton {
            visible: statusRow.kind === "error"
            label: "Logs"
            tooltip: "Open the xray journal in a terminal"
            Layout.alignment: Qt.AlignTop
            onClicked: xray.openLogs()
          }
        }

        // Keys in three groups, pinned so they are never a list's length
        // away. Shown once the keyboard is used (and on first run); `?`
        // hides or shows them. Mouse users get the keys in tooltips.
        Column {
          visible: root.firstRun || (xray.reachable && !root.legendHidden)
          width: parent.width
          spacing: Style.space(4)

          Repeater {
            model: root.firstRun ? [["", "Enter adds it · Esc twice closes"]]
                   : root.filterFocused ? [["FILTER", "↑/↓ · Enter connect · Ctrl+T test · Esc clear"]]
                   : root.urlFocused ? [["URL", "Enter adds it · Esc back to the list"]]
                   : !root.keyboardUser ? [["KEYS", "Ctrl+C on/off · type to filter · j/k move · ? hide"]]
                   : [["MOVE", "j/k · h/l · Enter apply · Home switch · ? hide"],
                      ["ACT", "Ctrl+C on/off · Ctrl+T test · Ctrl+R update"],
                      ["MANAGE", "Ctrl+A add sub · Ctrl+O config · Ctrl+L logs"]]
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
        anchors.topMargin: Style.space(12)
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height
        reuseItems: true
        spacing: Style.space(4)
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
          width: nodeList.width
          spacing: Style.space(12)
          bottomPadding: Style.space(6)

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
              label: root.settingsSummary + (root.settingsOpen ? "  󰅃" : "  󰅀")
              a11yName: (root.settingsOpen ? "Hide settings. " : "Show settings. ") + "Now: " + root.settingsSummary
              tooltip: root.settingsOpen ? "Hide mode, route and ad blocking" : "Change mode, route or ad blocking"
              hasCursor: root.cursorRow === "settings"
              onClicked: root.toggleSettings()
            }

            Item { Layout.fillWidth: true }
          }

          Column {
            visible: xray.reachable && !root.firstRun && root.settingsOpen
            width: parent.width
            spacing: Style.space(8)

            RowLayout {
              width: parent.width
              spacing: Style.space(8)

              PanelSectionHeader {
                text: "MODE"
                Layout.preferredWidth: root.settingLabelWidth
                Layout.alignment: Qt.AlignVCenter
                foreground: root.foreground
                fontFamily: root.fontFamily
              }

              ButtonGroup {
                options: root.modeOptions
                value: xray.mode
                cursorIndex: root.cursorRow === "mode" ? root.chipIndex : -1
                // the kit's chips carry no accessible names; the group says the state
                Accessible.role: Accessible.Grouping
                Accessible.name: "Mode: " + (xray.mode === "tun" ? "TUN, all system traffic" : "proxy")
                Accessible.description: "Options: proxy, TUN. h and l switch"
                Accessible.focusable: true
                Accessible.focused: cursorIndex >= 0
                focusable: false
                foreground: root.foreground
                fontFamily: root.fontFamily
                fontSize: Style.font.caption
                opacity: xray.busy ? 0.45 : 1.0
                onChanged: function(v) { root.chooseMode(v) }
                onHovered: function(i, h) { if (h) root.cursorActive = false }
              }

              Item { Layout.fillWidth: true }
            }

            RowLayout {
              width: parent.width
              spacing: Style.space(8)

              PanelSectionHeader {
                text: "ROUTE"
                Layout.preferredWidth: root.settingLabelWidth
                Layout.alignment: Qt.AlignVCenter
                foreground: root.foreground
                fontFamily: root.fontFamily
              }

              ButtonGroup {
                options: root.routeOptions
                value: xray.region ? "direct" : "global"
                cursorIndex: root.cursorRow === "route" && root.chipIndex < 2 ? root.chipIndex : -1
                Accessible.role: Accessible.Grouping
                Accessible.name: "Route: " + (xray.region ? xray.region.name + " sites go direct" : "everything through the VPN")
                Accessible.description: "Options: all through the VPN, one country direct. h and l switch"
                Accessible.focusable: true
                Accessible.focused: cursorIndex >= 0
                focusable: false
                foreground: root.foreground
                fontFamily: root.fontFamily
                fontSize: Style.font.caption
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
                onClicked: root.regionsOpen = !root.regionsOpen
                onHovered: function(h) { if (h) root.cursorActive = false }
                Accessible.role: Accessible.Button
                Accessible.name: root.regionsOpen ? "Hide the country list" : "Change the direct country"
              }

              Item { Layout.fillWidth: true }
            }

            Flow {
              visible: root.regionsOpen
              width: parent.width
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
                  onClicked: root.pickRegion(modelData.code)
                  onHovered: function(h) { if (h) { root.cursorActive = false; root.regionHover = index } }
                }
              }
            }

            Text {
              textFormat: Text.PlainText
              visible: root.regionsOpen
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

            RowLayout {
              width: parent.width
              spacing: Style.space(8)

              PanelSectionHeader {
                id: adblockLabel
                text: "ADBLOCK"
                Layout.preferredWidth: root.settingLabelWidth
                Layout.alignment: Qt.AlignVCenter
                foreground: root.foreground
                fontFamily: root.fontFamily
              }

              ToggleSwitch {
                id: adblockSwitch
                trackHeight: Math.round(adblockLabel.font.pixelSize * 1.2)
                cursorPad: Style.space(3)
                Layout.alignment: Qt.AlignVCenter
                checked: xray.adblock
                busy: xray.busy
                hasCursor: root.cursorRow === "ads"
                opacity: xray.busy || !(xray.geo || xray.adblock) ? 0.45 : 1.0
                foreground: root.foreground
                onToggled: if (xray.geo || xray.adblock) xray.setAdblock(!xray.adblock)
                onHovered: function(h) { if (h) root.cursorActive = false }
                Accessible.role: Accessible.CheckBox
                Accessible.name: "Ad blocking"
                Accessible.checked: xray.adblock
                Accessible.focusable: true
                Accessible.focused: hasCursor
              }

              Text {
                textFormat: Text.PlainText
                Layout.fillWidth: true
                text: xray.geo ? "Blocks known ad and tracker domains"
                               : "Needs geo data: install v2ray-geoip and v2ray-domain-list-community"
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                wrapMode: xray.geo ? Text.NoWrap : Text.WordWrap                // the package names are the point
                elide: xray.geo ? Text.ElideRight : Text.ElideNone

                // the whole line toggles, not just the small switch
                MouseArea {
                  id: adblockText
                  anchors.fill: parent
                  anchors.topMargin: -Style.space(6)
                  anchors.bottomMargin: -Style.space(6)
                  hoverEnabled: true
                  enabled: xray.geo || xray.adblock
                  cursorShape: Qt.PointingHandCursor
                  onClicked: if (!xray.busy) xray.setAdblock(!xray.adblock)
                  onEntered: root.cursorActive = false
                }
                PanelToolTip {
                  visible: adblockText.containsMouse
                  text: "Sends geosite:category-ads-all to a blackhole"
                  fontFamily: root.fontFamily
                }
              }
            }

            // Keyboard users never see hover tooltips: the chip under the
            // cursor explains itself here (and to a screen reader). One fixed
            // line below the settings, kept once the keyboard is in use, so
            // no row moves when the cursor crosses them.
            Text {
              id: chipHint
              textFormat: Text.PlainText
              visible: root.keyboardUser && !root.firstRun
              width: parent.width
              text: {
                var r = root.cursorRow, c = root.chipIndex
                if (r === "mode") return root.modeOptions[c].tooltip
                if (r === "route") return c < 2 ? root.routeOptions[c].tooltip : "Change the direct country"
                if (r === "settings") return root.settingsOpen ? "Enter hides the settings" : "Enter shows mode, route and ad blocking"
                if (r === "ads") return xray.geo ? "ADBLOCK: known ad and tracker domains" : "ADBLOCK needs the geo data packages"
                if (r === "hero") return root.killArmed ? "Enter again: traffic goes direct, unprotected"
                                          : xray.blocked ? "Waiting is safe: nothing leaks. Enter twice turns it off"
                                          : xray.connected ? "Enter disconnects" : "Enter connects"
                return " "                                // keeps the line's height
              }
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              elide: Text.ElideRight
              onTextChanged: function() { if (text.trim() !== "") Accessible.announce(text) }
            }
          }

          PanelSeparator { visible: xray.reachable && !root.firstRun; foreground: root.foreground }
          Column {
            visible: xray.reachable
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
                label: xray.testing ? "Stop · " + root.elapsedText : "Test"
                tooltip: xray.testing ? "Stop the latency test, finished results are kept (Ctrl+T)"
                         : (root.filterQuery !== "" ? "Latency-test the filtered nodes" : "Latency-test all nodes")
                           + (root.visibleNodes.length > 200 ? " (the first 200)" : "") + " (Ctrl+T)"
                enabled: xray.testing || (root.visibleNodes.length > 0 && !xray.busy)
                onClicked: xray.testNodes(root.visibleNodes)
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
                  if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_T) {
                    root.runCtrl("t")
                    event.accepted = true
                    return
                  }
                  // Esc clears and hands the keys back to the list (a second
                  // Esc there closes); Enter connects and does the same
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
              text: xray.touch === null ? "Loading…"
                    : root.filterQuery !== "" ? "No nodes match “" + root.filterQuery + "” — Esc clears the filter"
                    : root.firstRun ? "Paste your subscription URL below, or a single server: a vless://, vmess://, trojan://, ss:// or hysteria2:// link, or its Xray JSON config."
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

          PanelSectionHeader {
            visible: rowCol.groupTitle !== ""
            width: parent.width
            elide: Text.ElideRight
            text: rowCol.groupTitle
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          NodeRow { globalIndex: rowCol.index }
        }

        footer: Column {
          property alias subUrl: subUrlField
          width: nodeList.width
          spacing: Style.space(12)
          topPadding: Style.space(12)

          PanelSeparator { visible: xray.reachable; foreground: root.foreground }

          Column {
            visible: xray.reachable
            width: parent.width
            spacing: Style.space(6)

            RowLayout {
              width: parent.width
              spacing: Style.space(6)

              PanelSectionHeader {
                Layout.fillWidth: true
                text: "SUBSCRIPTIONS" + (xray.subs.length > 0 ? " · " + xray.subs.length + (root.subsShown ? " 󰅃" : " 󰅀") : "")
                foreground: root.foreground
                fontFamily: root.fontFamily

                MouseArea {
                  anchors.fill: parent
                  anchors.topMargin: -Style.space(6)       // a caption-high strip is too thin to hit
                  anchors.bottomMargin: -Style.space(6)
                  enabled: xray.subs.length > 0
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.subsOpen = !root.subsOpen
                  Accessible.role: Accessible.Button
                  Accessible.name: (root.subsShown ? "Collapse" : "Expand") + " subscriptions"
                  Accessible.onPressAction: root.subsOpen = !root.subsOpen
                }
              }

              TextActionButton {
                visible: root.subsShown
                label: "Open folder"
                tooltip: "Open ~/.config/omarchy-xray, where custom.json lives · Ctrl+O"
                hasCursor: root.cursorRow === "subs" && root.chipIndex === 0
                onClicked: xray.openWebUi()
              }

              TextActionButton {
                visible: root.subsShown && xray.subs.length > 0
                label: "Update all"
                tooltip: "Download every subscription again (Ctrl+R)"
                enabled: !xray.busy
                hasCursor: root.cursorRow === "subs" && root.chipIndex === 1
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
                placeholderText: "Subscription URL, vless:// link or Xray JSON"
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
                enabled: subUrlField.text.trim() !== "" && !xray.busy
                onClicked: root.importSub()
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
                      color: subRow.sub && subRow.sub.error ? root.errorColor : root.dim
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.bodySmall
                      elide: Text.ElideRight
                    }
                  }

                  TextActionButton {
                    visible: !subRow.sub.local            // Manual: nothing to download
                    label: "Update"
                    a11yName: "Update " + (subRow.sub.title || subRow.sub.host)
                    tooltip: "Download this subscription again"
                    enabled: !xray.busy
                    hasCursor: root.cursorSub === subRow.index && root.chipIndex === 0
                    onClicked: xray.updateSub(subRow.sub.index)
                  }

                  TextActionButton {
                    id: removeButton
                    readonly property bool armed: root.armedSub === subRow.index
                    // same width armed or not, so "Update" never shifts
                    Layout.preferredWidth: Math.ceil(confirmMetrics.advanceWidth) + 2 * Style.spacing.controlPaddingX
                    label: armed ? "Confirm" : "Remove"
                    a11yName: (armed ? "Confirm removing " : "Remove ") + (subRow.sub.title || subRow.sub.host)
                    onArmedChanged: if (armed) Accessible.announce("Press again to remove " + (subRow.sub.title || subRow.sub.host))
                    // armed reads as a state, not only as a different word
                    bordered: armed
                    selected: armed
                    tint: armed ? root.errorColor : root.foreground
                    tooltip: armed ? "Click again to remove " + (subRow.sub.title || subRow.sub.host) + " and its nodes"
                                   : subRow.sub.local ? "Remove every server added by hand"
                                   : "Remove this subscription and its nodes"
                    enabled: !xray.busy
                    hasCursor: root.cursorSub === subRow.index && root.chipIndex === (subRow.sub.local ? 0 : 1)
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
    // kit TextField height = line + 2 * (verticalPadding + 1 px border);
    // a NodeRow is line + rowPaddingX
    verticalPadding: Style.spacing.rowPaddingX / 2 - 1
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
  component TextActionButton: Button {
    property string label: ""
    property string a11yName: ""               // when the label alone is ambiguous
    property string tooltip: ""
    property color tint: root.foreground
    text: label
    tooltipText: tooltip
    foreground: enabled ? tint : root.dim
    fontFamily: root.fontFamily
    onHovered: function(h) { if (h) root.cursorActive = false }
    Accessible.role: Accessible.Button
    Accessible.name: a11yName !== "" ? a11yName : label
    Accessible.description: tooltip
    Accessible.focusable: true
    Accessible.focused: hasCursor
    Accessible.onPressAction: if (enabled) clicked()
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

    hasCursor: root.cursorActive && root.nodeIndex === globalIndex
    current: isConnected
    foreground: root.foreground
    fill: root.hoverFill
    currentFill: root.selectedFill
    width: parent ? parent.width : 0
    implicitHeight: rowInner.implicitHeight + Style.spacing.rowPaddingX
    Accessible.role: Accessible.Button
    Accessible.name: node ? node.name + (isConnected ? ", connected" : "") + (latencyText !== "" ? ", " + latencyText : "")
                            + (fastest ? ", fastest" : "") : ""
    // the panel's own cursor is the focus a screen reader should follow
    Accessible.focusable: true
    Accessible.focused: hasCursor
    Accessible.onPressAction: if (node) xray.connectNode(node)

    MouseArea {
      id: nodeMouse
      anchors.fill: parent
      acceptedButtons: Qt.LeftButton | Qt.RightButton
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onPositionChanged: function(mouse) {
        if (pointerGate.moved(nodeMouse, mouse)) root.setNodeCursor(nodeRow.globalIndex)
      }
      onClicked: function(mouse) {
        if (!nodeRow.node) return
        if (mouse.button === Qt.RightButton) xray.testNode(nodeRow.node)
        else xray.connectNode(nodeRow.node)
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
        text: nodeRow.isConnected ? "󰐾" : "󰐽"
        Accessible.ignored: true                  // the row's name says "connected"
        color: nodeRow.isConnected ? root.foreground : root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        Layout.alignment: Qt.AlignVCenter
      }

      Text {
        textFormat: Text.PlainText
        Layout.fillWidth: true
        text: nodeRow.node ? nodeRow.node.name : ""
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        font.bold: nodeRow.isConnected
        elide: Text.ElideRight
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

      Text {
        textFormat: Text.PlainText
        visible: !!nodeRow.node && nodeRow.node.key !== "auto"
        // Fixed, right-aligned cell: results line up and never shift the name.
        Layout.preferredWidth: root.latencyCellWidth
        horizontalAlignment: Text.AlignRight
        text: (nodeRow.fastest ? "󰉁 " : "") + nodeRow.latencyText
        Accessible.ignored: true
        color: nodeRow.latencyBadLat ? root.dim : root.foreground      // "timeout" says it; don't shout
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall      // the number nodes are chosen by
        font.bold: nodeRow.fastest
        Layout.alignment: Qt.AlignVCenter
      }
    }

    PanelToolTip {
      visible: nodeMouse.containsMouse && !!nodeRow.node
      text: (nodeRow.node && nodeRow.node.key !== "auto" && nodeRow.node.address
               ? nodeRow.node.address + (nodeRow.node.net ? " · " + nodeRow.node.net : "") + (nodeRow.fastest ? " · fastest" : "") + "\n" : "")
            + (nodeRow.isConnected ? "Connected · right-click to test latency" : "Click to connect · right-click to test latency")
      fontFamily: root.fontFamily
    }
  }
}
