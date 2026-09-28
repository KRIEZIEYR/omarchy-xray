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
  readonly property string lastNodeKey: settings ? String(settings.lastNodeKey || "") : ""

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property color hoverFill: bar ? Style.hoverFillFor(bar.foreground, Color.accent) : "transparent"
  readonly property color selectedFill: bar ? Style.selectedFillFor(bar.foreground, Color.accent) : "transparent"

  readonly property color vpnGreen: "#22c55e"
  readonly property color barIconColor: {
    if (!xray.reachable) return urgent
    if (xray.connected) return vpnGreen
    return Qt.darker(foreground, 1.55)
  }

  // Flat, filtered node list the cursor walks over.
  readonly property var visibleGroups: Model.filterNodes(xray.touch ? xray.touch.groups : [], filterQuery)
  readonly property var visibleNodes: {
    var out = []
    for (var g = 0; g < visibleGroups.length; g++)
      for (var i = 0; i < visibleGroups[g].nodes.length; i++) out.push(visibleGroups[g].nodes[i])
    return out
  }
  function selectedNode() {
    if (visibleNodes.length === 0) return null
    return visibleNodes[Math.max(0, Math.min(nodeIndex, visibleNodes.length - 1))]
  }

  function ensureCursor() {
    if (nodeIndex >= visibleNodes.length) nodeIndex = Math.max(0, visibleNodes.length - 1)
  }

  function moveNodeCursor(delta) {
    if (visibleNodes.length === 0) return
    cursorActive = true
    nodeIndex = Math.max(0, Math.min(visibleNodes.length - 1, nodeIndex + delta))
    scrollCursorIntoView()
  }

  function setNodeCursor(index) {
    cursorActive = true
    nodeIndex = index
    scrollCursorIntoView()
  }

  function activateCursor() {
    ensureCursor()
    var node = selectedNode()
    if (node) xray.connectNode(node)
  }

  function scrollItemIntoView(item) {
    if (!panelFlick || !item) return
    Qt.callLater(function() {
      if (!item) return
      var margin = Style.space(6)
      var point = item.mapToItem(panelFlick.contentItem, 0, 0)
      var top = point.y
      var bottom = top + item.height
      var viewTop = panelFlick.contentY
      var viewBottom = viewTop + panelFlick.height
      var maxY = Math.max(0, panelFlick.contentHeight - panelFlick.height)
      if (top < viewTop + margin) panelFlick.contentY = Math.max(0, top - margin)
      else if (bottom > viewBottom - margin) panelFlick.contentY = Math.min(maxY, bottom + margin - panelFlick.height)
    })
  }

  function scrollCursorIntoView() {
    var item = findNodeItem(column, root.nodeIndex)
    if (item) scrollItemIntoView(item)
  }

  function findNodeItem(item, idx) {
    if (!item || !item.children) return null
    for (var i = 0; i < item.children.length; i++) {
      var c = item.children[i]
      if (c.isNodeRow === true && c.globalIndex === idx) return c
      var found = findNodeItem(c, idx)
      if (found) return found
    }
    return null
  }

  function persistSetting(key, value) {
    if (!root.bar || !root.bar.shell || typeof root.bar.shell.updateEntryInline !== "function") return
    var entry = { id: root.moduleName }
    for (var k in settings) if (k !== "id") entry[k] = settings[k]
    entry[key] = value
    root.bar.shell.updateEntryInline(root.moduleName, entry)
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onOpenedChanged: if (opened) {
    cursorActive = false
    if (panelFlick) panelFlick.contentY = 0
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
    iconComponent: Component {
      Item {
        readonly property string label: {
          if (xray.barLabel === "node") return xray.connectedNodeName
          if (xray.barLabel === "speed")
            return xray.connected && xray.traffic !== null ? "↓" + Model.formatSpeed(xray.traffic.downSpeed) : ""
          return ""
        }
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
            warning: !xray.reachable
          }
          Text {
            id: labelText
            visible: row.parent.label !== ""
            text: row.parent.label
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
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(620))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function(dx, dy) {
        if (!root.cursorActive) { root.cursorActive = true; return }
        if (dy > 0) root.moveNodeCursor(1)
        else if (dy < 0) root.moveNodeCursor(-1)
      }
      onActivateRequested: if (root.cursorActive) root.activateCursor()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (t === "t" || t === "T") xray.testNodes(root.visibleNodes)
        else if (t === "u" || t === "U") xray.updateSubscriptions()
        else if (t === "c" || t === "C") xray.toggleConnection(root.lastNodeKey)
        else if (t === "w" || t === "W") xray.openWebUi()
        else if ((t === "j")) root.moveNodeCursor(1)
        else if ((t === "k")) root.moveNodeCursor(-1)
      }

      Flickable {
        id: panelFlick
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: column
          width: panelFlick.width
          spacing: Style.space(12)

          PanelHero {
            id: hero
            width: parent.width
            title: "Xray"
            meta: xray.actionStatus !== "" ? xray.actionStatus : xray.heroSummary
            metaOpacity: xray.actionStatus !== "" ? 0.75 : 1.0
            foreground: root.foreground
            fontFamily: root.fontFamily
            iconOpacity: xray.connected ? 1.0 : 0.5
            iconComponent: Component {
              XrayIcon {
                iconSize: Style.font.display
                color: xray.connected ? root.vpnGreen : hero.foreground
                opacity: xray.connected ? 1.0 : 0.55
              }
            }
            trailingControl: Component {
              ToggleSwitch {
                id: powerSwitch
                checked: xray.connected
                busy: xray.busy
                hasCursor: false
                foreground: hero.foreground
                onToggled: xray.toggleConnection(root.lastNodeKey)
              }
            }
          }

          Text {
            visible: xray.traffic !== null
            width: parent.width
            text: "↓ " + Model.formatSpeed(xray.traffic ? xray.traffic.downSpeed : 0)
                  + "   ↑ " + Model.formatSpeed(xray.traffic ? xray.traffic.upSpeed : 0)
                  + "   ·   " + Model.formatBytes(xray.traffic ? xray.traffic.downTotal : 0)
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
          }

          Text {
            visible: xray.lastError !== "" && xray.actionStatus === ""
            width: parent.width
            text: xray.lastError
            color: root.urgent
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          CursorSurface {
            visible: !xray.reachable
            width: parent.width
            implicitHeight: setupHint.implicitHeight + Style.spacing.rowPaddingX
            foreground: root.foreground

            Text {
              id: setupHint
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              anchors.margins: Style.space(12)
              text: "Xray manager not found. Reinstall the widget: ./install.sh"
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              wrapMode: Text.WordWrap
            }
          }

          RowLayout {
            visible: xray.reachable
            width: parent.width
            spacing: Style.space(6)

            ModeButton {
              Layout.fillWidth: true
              modeName: "proxy"
              label: "PROXY"
              tooltip: "Apps connect through the local socks/http proxy"
            }
            ModeButton {
              Layout.fillWidth: true
              modeName: "tun"
              label: "TUN"
              tooltip: xray.tunInstalled
                       ? "Route all system traffic through the tunnel"
                       : "Route all system traffic — needs a one-time setup (polkit prompt)"
            }
          }

          RowLayout {
            visible: xray.reachable
            width: parent.width
            spacing: Style.space(6)

            ChoiceButton {
              Layout.fillWidth: true
              label: "GLOBAL"
              current: xray.routing === "global"
              tooltip: "Everything except private networks goes through the proxy"
              onClicked: if (!current) xray.setRouting("global")
            }
            ChoiceButton {
              Layout.fillWidth: true
              label: "RU DIRECT"
              current: xray.routing === "ru-direct"
              tooltip: xray.geo ? "Russian sites and IPs (geosite/geoip) go direct"
                                : ".ru/.su/.рф go direct (install xray geo data for full lists)"
              onClicked: if (!current) xray.setRouting("ru-direct")
            }
            ChoiceButton {
              Layout.fillWidth: true
              label: "ADBLOCK"
              current: xray.adblock
              enabled: xray.geo || xray.adblock
              tooltip: xray.geo ? "Block geosite:category-ads-all" : "Needs xray geo data (geosite.dat)"
              onClicked: xray.setAdblock(!xray.adblock)
            }
          }

          Text {
            visible: xray.reachable && xray.skippedText !== ""
            width: parent.width
            text: xray.skippedText
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }

          Column {
            visible: xray.reachable
            width: parent.width
            spacing: Style.space(4)

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
                label: "Test"
                enabled: root.visibleNodes.length > 0 && !xray.busy
                onClicked: xray.testNodes(root.visibleNodes)
              }
            }

            RowLayout {
              width: parent.width
              spacing: Style.space(6)

              TextField {
                id: searchField
                Layout.fillWidth: true
                foreground: root.foreground
                placeholderText: "Filter nodes…"
                text: root.filterQuery
                onTextChanged: {
                  root.filterQuery = text
                  root.nodeIndex = 0
                }
                Keys.onPressed: function(event) {
                  if (event.key === Qt.Key_Escape) {
                    root.close()
                    event.accepted = true
                    return
                  }
                  if (event.key === Qt.Key_Down || event.text === "j") {
                    root.moveNodeCursor(1)
                    event.accepted = true
                    return
                  }
                  if (event.key === Qt.Key_Up || event.text === "k") {
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
                label: "✕"
                tooltip: "Clear filter"
                enabled: root.filterQuery !== ""
                onClicked: { root.filterQuery = ""; searchField.text = ""; keyCatcher.forceActiveFocus() }
              }
            }

            Repeater {
              model: root.visibleGroups.length
              delegate: Column {
                id: groupCol
                required property int index
                readonly property var group: root.visibleGroups[index]
                readonly property int baseIndex: {
                  var n = 0
                  for (var g = 0; g < index; g++) n += root.visibleGroups[g].nodes.length
                  return n
                }
                readonly property string groupSubtitle: {
                  var st = groupCol.group ? groupCol.group.status : null
                  if (st === null || st === undefined) return ""
                  var str = String(st).trim()
                  if (str === "" || str === "undefined" || str === "null") return ""
                  return "  ·  " + str
                }
                width: parent.width
                spacing: Style.space(4)

                PanelSectionHeader {
                  text: groupCol.group.title + groupCol.groupSubtitle
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                }

                Repeater {
                  model: groupCol.group.nodes.length
                  delegate: NodeRow { globalIndex: groupCol.baseIndex + index }
                }
              }
            }

            Text {
              visible: root.visibleNodes.length === 0
              width: parent.width
              text: xray.touch === null ? "Loading…" : "No nodes yet — add a subscription URL below."
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              horizontalAlignment: Text.AlignHCenter
            }
          }

          Column {
            visible: xray.reachable
            width: parent.width
            spacing: Style.space(4)

            RowLayout {
              width: parent.width
              spacing: Style.space(6)

              PanelSectionHeader {
                Layout.fillWidth: true
                text: "SUBSCRIPTIONS"
                foreground: root.foreground
                fontFamily: root.fontFamily
              }

              TextActionButton {
                label: "Folder"
                tooltip: "Open ~/.config/omarchy-xray (custom.json lives here)"
                onClicked: xray.openWebUi()
              }

              TextActionButton {
                label: "Update all"
                enabled: !xray.busy
                onClicked: xray.updateSubscriptions()
              }
            }

            RowLayout {
              width: parent.width
              spacing: Style.space(6)

              TextField {
                id: subUrlField
                Layout.fillWidth: true
                foreground: root.foreground
                placeholderText: "Subscription URL — add or replace"
                onAccepted: {
                  if (text.trim() !== "") { xray.importUrl(text.trim()); text = "" }
                }
                Keys.onEscapePressed: function(event) {
                  root.close()
                  event.accepted = true
                }
              }

              TextActionButton {
                label: "Add"
                enabled: subUrlField.text.trim() !== "" && !xray.busy
                onClicked: {
                  xray.importUrl(subUrlField.text.trim())
                  subUrlField.text = ""
                }
              }
            }

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
                    text: "●"
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                  }

                  ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Style.space(1)

                    Text {
                      Layout.fillWidth: true
                      text: subRow.sub ? (subRow.sub.title || subRow.sub.host) : ""
                      color: root.foreground
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.body
                      elide: Text.ElideRight
                    }

                    Text {
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
                    enabled: !xray.busy
                    onClicked: xray.updateSub(subRow.sub.index)
                  }

                  TextActionButton {
                    label: "✕"
                    tooltip: "Remove subscription"
                    enabled: !xray.busy
                    onClicked: xray.subRemove(subRow.sub.index)
                  }
                }
              }
            }
          }

          Text {
            width: parent.width
            text: "j/k move · Enter connect · t test · u update subs · c connect/disconnect · w config folder"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            horizontalAlignment: Text.AlignHCenter
            opacity: 0.8
          }
        }
      }
    }
  }

  component ModeButton: CursorSurface {
    id: modeButton
    property string modeName: ""
    property string label: ""
    property string tooltip: ""
    foreground: root.foreground
    fill: root.hoverFill
    currentFill: root.selectedFill
    current: xray.mode === modeName
    hasCursor: modeMouse.containsMouse
    implicitHeight: modeLabel.implicitHeight + Style.spacing.rowPaddingX

    MouseArea {
      id: modeMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: xray.busy ? Qt.ArrowCursor : Qt.PointingHandCursor
      enabled: !xray.busy
      onClicked: if (xray.mode !== modeButton.modeName) xray.setMode(modeButton.modeName)
    }

    Text {
      id: modeLabel
      anchors.centerIn: parent
      text: modeButton.label
      color: modeButton.current ? root.foreground : (modeMouse.containsMouse ? root.foreground : root.dim)
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
      font.bold: modeButton.current
    }

    PanelToolTip {
      visible: modeMouse.containsMouse && modeButton.tooltip !== ""
      text: modeButton.tooltip
      fontFamily: root.fontFamily
    }
  }

  component ChoiceButton: CursorSurface {
    id: choice
    property string label: ""
    property string tooltip: ""
    signal clicked()
    foreground: root.foreground
    fill: root.hoverFill
    currentFill: root.selectedFill
    hasCursor: choiceMouse.containsMouse
    implicitHeight: choiceLabel.implicitHeight + Style.spacing.rowPaddingX

    MouseArea {
      id: choiceMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: xray.busy || !choice.enabled ? Qt.ArrowCursor : Qt.PointingHandCursor
      enabled: !xray.busy && choice.enabled
      onClicked: choice.clicked()
    }

    Text {
      id: choiceLabel
      anchors.centerIn: parent
      text: choice.label
      color: choice.current ? root.foreground : (choiceMouse.containsMouse ? root.foreground : root.dim)
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      font.bold: choice.current
    }

    PanelToolTip {
      visible: choiceMouse.containsMouse && choice.tooltip !== ""
      text: choice.tooltip
      fontFamily: root.fontFamily
    }
  }

  component TextActionButton: CursorSurface {
    id: textAction
    property string label: ""
    property string tooltip: ""
    signal clicked()
    foreground: root.foreground
    fill: root.hoverFill
    currentFill: root.selectedFill
    hasCursor: textActionMouse.containsMouse
    implicitHeight: textActionLabel.implicitHeight + Style.spacing.rowPaddingX
    implicitWidth: textActionLabel.implicitWidth + Style.space(16)

    MouseArea {
      id: textActionMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: textAction.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
      enabled: textAction.enabled
      onClicked: textAction.clicked()
    }

    Text {
      id: textActionLabel
      anchors.centerIn: parent
      text: textAction.label
      color: textAction.enabled ? root.foreground : root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
    }

    PanelToolTip {
      visible: textActionMouse.containsMouse && textAction.tooltip !== ""
      text: textAction.tooltip
      fontFamily: root.fontFamily
    }
  }

  component NodeRow: CursorSurface {
    id: nodeRow
    required property int index
    property int globalIndex: index
    readonly property var node: {
      // Index into the already-flattened cursor list (same order the cursor walks).
      var flat = root.visibleNodes
      return globalIndex < flat.length ? flat[globalIndex] : null
    }
    readonly property bool isNodeRow: true
    readonly property bool isConnected: node !== null && node.connected === true
    readonly property string latencyText: node ? Model.latencyLabel(node.latency) : ""
    readonly property bool latencyOk: node ? Model.latencyGood(latencyText) : false
    readonly property bool latencyBadLat: node ? Model.latencyBad(latencyText) : false
    readonly property string subtitle: {
      if (!node) return ""
      var parts = []
      if (node.address !== "") parts.push(node.address)
      if (node.net !== "") parts.push(node.net)
      return parts.join(" · ")
    }

    hasCursor: root.cursorActive && root.nodeIndex === globalIndex
    current: isConnected
    foreground: root.foreground
    fill: root.hoverFill
    currentFill: root.selectedFill
    width: parent ? parent.width : 0
    implicitHeight: rowInner.implicitHeight + Style.spacing.rowPaddingX

    MouseArea {
      id: nodeMouse
      anchors.fill: parent
      acceptedButtons: Qt.LeftButton | Qt.RightButton
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onEntered: root.setNodeCursor(nodeRow.globalIndex)
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
        text: nodeRow.isConnected ? "●" : "○"
        color: nodeRow.isConnected ? root.foreground : root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        Layout.alignment: Qt.AlignVCenter
      }

      ColumnLayout {
        Layout.fillWidth: true
        spacing: Style.space(1)

        Text {
          Layout.fillWidth: true
          text: nodeRow.node ? nodeRow.node.name : ""
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          font.bold: nodeRow.isConnected
          elide: Text.ElideRight
        }

        Text {
          Layout.fillWidth: true
          visible: nodeRow.subtitle !== ""
          text: nodeRow.subtitle
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }

      Text {
        visible: nodeRow.latencyText !== ""
        text: nodeRow.latencyText
        color: nodeRow.latencyBadLat ? root.urgent : (nodeRow.latencyOk ? root.dim : root.foreground)
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        Layout.alignment: Qt.AlignVCenter
      }
    }

    PanelToolTip {
      visible: nodeMouse.containsMouse && nodeRow.node !== null && nodeRow.node.address !== ""
      text: nodeRow.node ? nodeRow.node.address + " · " + nodeRow.node.net + " — left click to connect, right click to test" : ""
      fontFamily: root.fontFamily
    }
  }
}
