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
  property int nodeIndex: 0
  property string filterQuery: ""
  property bool regionsOpen: false
  property int regionHover: -1
  property bool subsOpen: false
  readonly property bool subsShown: subsOpen || xray.subs.length === 0
  readonly property real settingLabelWidth: Style.space(52)
  readonly property string lastRegion: settings ? String(settings.lastRegion || "") : ""
  // BYPASS remembers its country, so ALL <-> BYPASS is one click.
  readonly property var routeRegion: {
    if (xray.region) return xray.region
    for (var i = 0; i < xray.regions.length; i++)
      if (xray.regions[i].code === lastRegion) return xray.regions[i]
    return null
  }

  function pickRegion(code) {
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

  // The cursor walks the settings rows above the nodes, as in Network:
  // nodeIndex < 0 addresses a settings row (-1 = the last one), >= 0 a node.
  // h/l pick a chip inside the row, Enter applies it.
  readonly property var settingRows: regionsOpen ? ["mode", "route", "regions"] : ["mode", "route"]
  property int chipIndex: 0
  readonly property string cursorRow: cursorActive && nodeIndex < 0 ? (settingRows[settingRows.length + nodeIndex] || "") : ""

  function chipCount(row) {
    return row === "mode" ? 2 : row === "route" ? 4 : row === "regions" ? xray.regions.length : 0
  }

  function currentChip(row) {
    if (row === "mode") return xray.mode === "tun" ? 1 : 0
    if (row === "route") return xray.region ? 1 : 0
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
    if (cursorRow === "mode") chooseMode(chipIndex === 1 ? "tun" : "proxy")
    else if (cursorRow === "route") {
      if (chipIndex < 2) chooseRoute(chipIndex === 1 ? "direct" : "global")
      else if (chipIndex === 2) regionsOpen = !regionsOpen
      else if (xray.geo || xray.adblock) xray.setAdblock(!xray.adblock)
    } else if (cursorRow === "regions" && xray.regions[chipIndex]) pickRegion(xray.regions[chipIndex].code)
  }

  // Opening or closing the country grid adds or removes a row above the
  // nodes; keep the cursor on the row it was on (a closed grid hands back
  // to its COUNTRY chip).
  onRegionsOpenChanged: {
    if (nodeIndex >= 0) return
    if (regionsOpen) nodeIndex -= 1
    else if (nodeIndex === -1) chipIndex = 2
    else nodeIndex += 1
  }
  readonly property string lastNodeKey: settings ? String(settings.lastNodeKey || "") : ""

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.4)   // the kit's secondary grey
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
  readonly property color barIconColor: {
    if (!xray.reachable) return urgent
    if (xray.connected) return onColor
    return foreground            // "off" is carried by the button's kit dimming
  }

  readonly property string barLabelText: {
    if (xray.barLabel === "node") return xray.connectedNodeName
    if (xray.barLabel === "speed" && xray.connected)
      return "󰁅" + (xray.traffic !== null ? Model.formatSpeed(xray.traffic.downSpeed) : "…")
    return ""
  }
  // The speed label reserves its widest value so the bar never jitters;
  // node names are capped and elided.
  TextMetrics {
    id: labelMetrics
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
    text: xray.barLabel === "speed" ? "󰁅1023.9 KB/s" : root.barLabelText
  }
  readonly property real barLabelWidth: barLabelText === "" ? 0 : Math.min(Math.ceil(labelMetrics.advanceWidth), Style.space(120))

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
      var title = grp.title + (st === "" || st === "undefined" || st === "null" ? "" : "  ·  " + st)
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
    // Clamp only against real rows: an empty list at startup must not park
    // the cursor on a settings row.
    if (visibleNodes.length > 0 && nodeIndex >= visibleNodes.length) nodeIndex = visibleNodes.length - 1
  }

  function moveNodeCursor(delta) {
    pointerGate.reset()
    cursorActive = true
    var next = Math.max(-settingRows.length, Math.min(visibleNodes.length - 1, nodeIndex + delta))
    if (next === nodeIndex) return
    nodeIndex = next
    if (nodeIndex < 0) {
      chipIndex = currentChip(cursorRow)
      nodeList.positionViewAtBeginning()
    } else {
      nodeList.positionViewAtIndex(nodeIndex, ListView.Contain)
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

  function activateCursor() {
    if (nodeIndex < 0) { activateChip(); return }
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
    nodeIndex = 0
    pointerGate.reset()
    regionsOpen = false
    nodeList.positionViewAtBeginning()
    xray.panelOpen = true
    xray.refresh()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
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
      var nodes = root.visibleNodes
      for (var i = 0; i < nodes.length; i++) {
        if (nodes[i].name.toLowerCase().indexOf(q) !== -1) { xray.connectNode(nodes[i]); return "ok" }
      }
      return "no node matches: " + name
    }
    function test(): string { xray.testNodes(root.visibleNodes); return "ok" }
    function updateSubs(): string { xray.updateSubscriptions(); return "ok" }
    function startCore(): string { xray.startCore(); return "ok" }
    function stopCore(): string { xray.stopCore(); return "ok" }
    function importUrl(url: string): string { xray.importUrl(url); return "ok" }
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
    // The kit slot fits an icon only; widen it by exactly the label so the
    // label no longer paints over the neighbouring widget.
    fixedWidth: vertical ? -1 : slotSize + (root.barLabelWidth > 0 ? root.barLabelWidth + Style.space(5) : 0)
    dimmed: xray.reachable && (!xray.connected || xray.pending !== "")
    tooltipText: xray.pending !== "" ? xray.actionStatus : xray.heroSummary
    iconComponent: Component {
      Item {
        readonly property string label: root.barLabelText
        implicitWidth: row.implicitWidth
        implicitHeight: Math.max(iconGlyph.implicitHeight, labelText.implicitHeight)
        Row {
          id: row
          anchors.centerIn: parent
          spacing: Style.space(5)
          XrayIcon {
            id: iconGlyph
            anchors.verticalCenter: parent.verticalCenter
            iconSize: Style.space(11)
            color: root.barIconColor
            filled: xray.connected
            warning: !xray.reachable
          }
          Text {
            textFormat: Text.PlainText
            id: labelText
            visible: row.parent.label !== ""
            text: row.parent.label
            width: root.barLabelWidth
            color: root.barIconColor
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
            anchors.verticalCenter: parent.verticalCenter
          }
        }
      }
    }
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton) xray.toggleConnection(root.lastNodeKey)
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
    contentHeight: panel.fittedContentHeight(nodeList.contentHeight, Style.space(620))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function(dx, dy) {
        if (!root.cursorActive) { root.cursorActive = true; return }
        if (dy !== 0) root.moveNodeCursor(dy > 0 ? 1 : -1)
        else if (dx !== 0) root.moveChip(dx)
      }
      onActivateRequested: if (root.cursorActive) root.activateCursor()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (t === "t" || t === "T") xray.testNodes(root.visibleNodes)
        else if (t === "u" || t === "U") xray.updateSubscriptions()
        else if (t === "c" || t === "C") xray.toggleConnection(root.lastNodeKey)
        else if (t === "w" || t === "W") xray.openWebUi()
        else if (t === "/" && nodeList.headerItem) nodeList.headerItem.search.forceActiveFocus()
      }

      // One scroll view for the whole panel. Only the node rows are
      // virtualized (1000 rows in a Column cost ~0.3 s per rebuild); the
      // controls above and the subscriptions below ride along as header and
      // footer so everything still scrolls together.
      ListView {
        id: nodeList
        anchors.fill: parent
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height
        reuseItems: true
        spacing: Style.space(4)
        currentIndex: -1                   // the panel keeps its own cursor (nodeIndex)
        // The header grows upward (status line, country grid): a view resting
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

          PanelHero {
            id: hero
            width: parent.width
            title: xray.heroTitle
            meta: xray.heroState
            foreground: root.foreground
            fontFamily: root.fontFamily
            iconOpacity: xray.connected ? 1.0 : 0.5
            iconComponent: Component {
              XrayIcon {
                iconSize: Style.font.display
                color: xray.connected ? root.onColor : hero.foreground
                filled: xray.connected
              }
            }
            trailingControl: Component {
              ToggleSwitch {
                id: powerSwitch
                checked: xray.connected
                busy: xray.toggleBusy
                opacity: xray.toggleBusy ? 0.5 : 1.0
                hasCursor: false
                foreground: hero.foreground
                onToggled: xray.toggleConnection(root.lastNodeKey)
              }
            }
          }

          // Status line: what is running now (sentence case, wraps), else the
          // last error with a glyph so it does not rely on colour alone.
          Text {
            textFormat: Text.PlainText
            visible: xray.actionStatus !== "" || xray.errorText !== ""
            width: parent.width
            text: xray.actionStatus !== "" ? xray.actionStatus : "󰀦 " + xray.errorText
            color: xray.actionStatus !== "" ? root.dim : root.urgent
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          Text {
            textFormat: Text.PlainText
            readonly property bool live: xray.connected && xray.traffic !== null
            visible: xray.reachable
            width: parent.width
            text: !live ? "󰁅 —   󰁝 —"
                  : "󰁅 " + Model.formatSpeed(xray.traffic.downSpeed)
                    + "   󰁝 " + Model.formatSpeed(xray.traffic.upSpeed)
                    + "   ·   " + Model.formatBytes(xray.traffic.downTotal)
            color: live ? root.foreground : root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
          }

          PanelSeparator { visible: xray.reachable; foreground: root.foreground }

          // Mode and route are set-and-forget: a compact label/chips form that
          // stays quieter than the connect switch and the node list.
          Column {
            visible: xray.reachable
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
                options: [
                  { value: "proxy", label: "PROXY",
                    tooltip: "Apps that use the system proxy go through the VPN (socks 127.0.0.1:20170, http :20171)" },
                  { value: "tun", label: "TUN",
                    tooltip: xray.tunInstalled ? "All system traffic goes through the VPN"
                           : "All system traffic goes through the VPN. The first switch asks for your password once" }
                ]
                value: xray.mode
                cursorIndex: root.cursorRow === "mode" ? root.chipIndex : -1
                focusable: false
                foreground: root.foreground
                fontFamily: root.fontFamily
                fontSize: Style.font.caption
                opacity: xray.busy ? 0.45 : 1.0
                onChanged: function(v) { root.chooseMode(v) }
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
                options: [
                  { value: "global", label: "ALL",
                    tooltip: "Everything goes through the VPN, except your local network" },
                  { value: "direct", label: "BYPASS",
                    tooltip: root.routeRegion ? root.routeRegion.name + ": its sites and IPs bypass the VPN"
                                              : "Let one country's sites and IPs bypass the VPN" }
                ]
                value: xray.region ? "direct" : "global"
                cursorIndex: root.cursorRow === "route" && root.chipIndex < 2 ? root.chipIndex : -1
                focusable: false
                foreground: root.foreground
                fontFamily: root.fontFamily
                fontSize: Style.font.caption
                opacity: xray.busy ? 0.45 : 1.0
                onChanged: function(v) { root.chooseRoute(v) }
              }

              Button {
                text: (root.routeRegion ? root.routeRegion.code.toUpperCase() : "COUNTRY") + (root.regionsOpen ? " 󰅃" : " 󰅀")
                tooltipText: "Choose the country that bypasses the VPN"
                bordered: true
                foreground: xray.region ? root.foreground : root.dim
                hasCursor: root.cursorRow === "route" && root.chipIndex === 2
                enabled: xray.regions.length > 0
                fontFamily: root.fontFamily
                fontSize: Style.font.caption
                onClicked: root.regionsOpen = !root.regionsOpen
              }

              Item { Layout.fillWidth: true }

              PanelSectionHeader {
                id: adblockLabel
                text: "ADBLOCK"
                Layout.alignment: Qt.AlignVCenter
                opacity: xray.geo || xray.adblock ? 1.0 : 0.45
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
                hasCursor: root.cursorRow === "route" && root.chipIndex === 3
                opacity: xray.busy || !(xray.geo || xray.adblock) ? 0.45 : 1.0
                foreground: root.foreground
                onToggled: if (xray.geo || xray.adblock) xray.setAdblock(!xray.adblock)

                PanelToolTip {
                  visible: adblockSwitch.containsMouse
                  text: xray.geo ? "Block ads and trackers (geosite:category-ads-all)"
                                 : "Needs Xray geo data (geosite.dat). Run omarchy-xray doctor to see what is missing"
                  fontFamily: root.fontFamily
                }
              }
            }

            Flow {
              visible: root.regionsOpen
              width: parent.width
              spacing: Style.space(4)

              Repeater {
                model: xray.regions
                delegate: Button {
                  required property var modelData
                  required property int index
                  text: modelData.code.toUpperCase()
                  hasCursor: root.cursorRow === "regions" && root.chipIndex === index
                  tooltipText: modelData.name + ": sites and IPs bypass the VPN"
                               + (xray.geo ? "" : " (domains only: no geo data installed)")
                  bordered: true
                  selected: xray.routing === modelData.code + "-direct"
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                  fontSize: Style.font.caption
                  onClicked: root.pickRegion(modelData.code)
                  onHovered: function(h) { root.regionHover = h ? index : (root.regionHover === index ? -1 : root.regionHover) }
                }
              }
            }

            Text {
              textFormat: Text.PlainText
              visible: root.regionsOpen
              width: parent.width
              text: {
                var i = root.cursorRow === "regions" ? root.chipIndex : root.regionHover
                var r = i >= 0 ? xray.regions[i] : null
                if (r) return r.name + ": its sites and IPs bypass the VPN" + (xray.geo ? "" : " (domains only, no geo data)")
                return root.routeRegion ? "Bypassing now: " + root.routeRegion.name : "Pick a country to bypass the VPN"
              }
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
            }
          }

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
                text: "NODES"
                foreground: root.foreground
                fontFamily: root.fontFamily
              }

              TextActionButton {
                label: xray.testing ? "Stop · " + root.elapsedText : "Test"
                tooltip: xray.testing ? "Stop the latency test (finished results are kept)"
                         : root.filterQuery !== "" ? "Latency-test the filtered nodes" : "Latency-test all nodes"
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
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
            }

            RowLayout {
              width: parent.width
              spacing: Style.space(6)

              TextField {
                id: searchField
                Layout.fillWidth: true
                foreground: root.foreground
                placeholderText: "Filter nodes…  ( / )"
                text: root.filterQuery
                onTextChanged: {
                  root.filterQuery = text
                  root.nodeIndex = 0
                }
                Keys.onPressed: function(event) {
                  if (event.key === Qt.Key_Escape) {
                    if (text !== "") text = ""
                    else root.close()
                    event.accepted = true
                    return
                  }
                  if (event.key === Qt.Key_Down) {
                    root.moveNodeCursor(1)
                    event.accepted = true
                    return
                  }
                  if (event.key === Qt.Key_Up) {
                    root.moveNodeCursor(-1)
                    event.accepted = true
                    return
                  }
                  if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                    root.activateCursor()
                    event.accepted = true
                  }
                }
              }

              TextActionButton {
                label: "󰅖"
                tooltip: "Clear filter"
                enabled: root.filterQuery !== ""
                onClicked: { root.filterQuery = ""; searchField.text = ""; keyCatcher.forceActiveFocus() }
              }
            }

            Text {
              textFormat: Text.PlainText
              visible: root.visibleNodes.length === 0
              width: parent.width
              text: xray.touch === null ? "Loading…"
                    : root.filterQuery !== "" ? "No nodes match “" + root.filterQuery + "” — Esc clears the filter"
                    : "No nodes yet — add a subscription URL below."
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
          readonly property string groupTitle: index < root.visibleRows.length ? root.visibleRows[index].title : ""
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
                  enabled: xray.subs.length > 0
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.subsOpen = !root.subsOpen
                  Accessible.role: Accessible.Button
                  Accessible.name: (root.subsShown ? "Collapse" : "Expand") + " subscriptions"
                  Accessible.onPressAction: root.subsOpen = !root.subsOpen
                }
              }

              TextActionButton {
                label: "Config"
                tooltip: "Open the config folder (~/.config/omarchy-xray, where custom.json lives)"
                onClicked: xray.openWebUi()
              }

              TextActionButton {
                label: "Update all"
                enabled: !xray.busy
                onClicked: xray.updateSubscriptions()
              }
            }

            RowLayout {
              visible: root.subsShown
              width: parent.width
              spacing: Style.space(6)

              TextField {
                id: subUrlField
                Layout.fillWidth: true
                foreground: root.foreground
                placeholderText: "Paste a subscription URL (https://…)"
                onAccepted: if (text.trim() !== "") root.importSub()
                Keys.onEscapePressed: function(event) {
                  root.close()
                  event.accepted = true
                }
              }

              TextActionButton {
                label: "Add"
                enabled: subUrlField.text.trim() !== "" && !xray.busy
                onClicked: root.importSub()
              }
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
                      text: subRow.sub ? (subRow.sub.error ? "⚠ " + subRow.sub.error : Model.subInfoLabel(subRow.sub.info)) : ""
                      color: subRow.sub && subRow.sub.error ? root.urgent : root.dim
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                      elide: Text.ElideRight
                    }
                  }

                  TextActionButton {
                    label: "Update"
                    tooltip: "Download this subscription again"
                    enabled: !xray.busy
                    onClicked: xray.updateSub(subRow.sub.index)
                  }

                  // Removal can't be undone (the URL is a secret the user would have
                  // to find again), so it takes a second click on the same spot.
                  TextActionButton {
                    id: removeButton
                    property bool armed: false
                    label: armed ? "Confirm remove" : "Remove"
                    tint: armed ? root.urgent : root.foreground
                    tooltip: armed ? "Click again to remove " + (subRow.sub.title || subRow.sub.host) + " and its nodes"
                                   : "Remove this subscription and its nodes"
                    enabled: !xray.busy
                    onClicked: {
                      if (!armed) { armed = true; disarm.restart(); return }
                      armed = false
                      xray.subRemove(subRow.sub.index)
                    }
                    Timer { id: disarm; interval: 4000; onTriggered: removeButton.armed = false }
                  }
                }
              }
            }
            }
          }

          Text {
            textFormat: Text.PlainText
            width: parent.width
            text: "j/k move · h/l choose · Enter apply · / filter · t test/stop · u update subs · c connect/disconnect · w config folder"
            wrapMode: Text.WordWrap
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            horizontalAlignment: Text.AlignHCenter
          }
        }
      }
    }
  }

  // Text action on the kit's Button (hover, cursor, tooltip), plus a tint
  // for destructive confirmation and a dimmed disabled state.
  component TextActionButton: Button {
    property string label: ""
    property string tooltip: ""
    property color tint: root.foreground
    text: label
    tooltipText: tooltip
    foreground: enabled ? tint : root.dim
    fontFamily: root.fontFamily
    Accessible.role: Accessible.Button
    Accessible.name: label
    Accessible.description: tooltip
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
    readonly property bool isConnected: node !== null && node.connected === true
    readonly property string latencyText: node ? Model.latencyLabel(node.latency) : ""
    readonly property bool latencyOk: node ? Model.latencyGood(latencyText) : false
    readonly property bool latencyBadLat: node ? Model.latencyBad(latencyText) : false
    // Auto's "address" is its member count, which says more than "balancer".
    readonly property string transport: !node ? "" : node.key === "auto" ? node.address : node.net

    hasCursor: root.cursorActive && root.nodeIndex === globalIndex
    current: isConnected
    foreground: root.foreground
    fill: root.hoverFill
    currentFill: root.selectedFill
    width: parent ? parent.width : 0
    implicitHeight: rowInner.implicitHeight + Style.spacing.rowPaddingX
    Accessible.role: Accessible.Button
    Accessible.name: node ? node.name + (isConnected ? ", connected" : "") + (latencyText !== "" ? ", " + latencyText : "") : ""
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
        visible: nodeRow.transport !== ""
        Layout.maximumWidth: rowInner.width * 0.4
        text: nodeRow.transport
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        elide: Text.ElideLeft
        Layout.alignment: Qt.AlignVCenter
      }

      Text {
        textFormat: Text.PlainText
        visible: nodeRow.latencyText !== ""
        text: nodeRow.latencyText
        color: nodeRow.latencyBadLat ? root.urgent : (nodeRow.latencyOk ? root.foreground : root.dim)
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        Layout.alignment: Qt.AlignVCenter
      }
    }

    PanelToolTip {
      visible: nodeMouse.containsMouse && nodeRow.node !== null
      text: (nodeRow.node && nodeRow.node.key !== "auto" && nodeRow.node.address ? nodeRow.node.address + " · " : "")
            + (nodeRow.isConnected ? "Connected · right-click to test latency" : "Click to connect · right-click to test latency")
      fontFamily: root.fontFamily
    }
  }
}
