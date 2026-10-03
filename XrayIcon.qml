import QtQuick
import qs.Commons
import qs.Ui

/*
 * Tunnel mark (arches over a ground line) drawn with Canvas primitives — no
 * fonts, no SVG, so it renders identically in tiny bar slots and in the
 * panel hero. Geometry is on a 24-unit grid.
 */
Item {
  id: root

  property real iconSize: Style.font.icon
  property color color: Color.foreground
  property bool warning: false
  // Connected state by shape, not hue: a solid tunnel with its inner arches
  // cut out stays distinct in monochrome themes where "on" and "off" share a grey.
  property bool filled: false
  // proxy mode protects only apps that use the system proxy: half a tunnel
  property bool half: false
  property color badgeColor: Color.urgent

  width: iconSize
  height: iconSize
  implicitWidth: iconSize
  implicitHeight: iconSize

  Canvas {
    id: canvas
    anchors.fill: parent
    antialiasing: true

    onPaint: {
      var ctx = canvas.getContext("2d")
      ctx.reset()
      var k = canvas.width / 24
      ctx.lineWidth = Math.max(1.2, 1.5 * k)
      ctx.strokeStyle = root.color
      ctx.fillStyle = root.color
      ctx.lineJoin = "round"
      ctx.lineCap = "round"

      // an arch from (x0, bottom) up, over a half circle, back down to bottom
      function arch(x0, x1, top, bottom) {
        var r = (x1 - x0) / 2
        ctx.moveTo(x0 * k, bottom * k)
        ctx.lineTo(x0 * k, (top + r) * k)
        ctx.arc((x0 + r) * k, (top + r) * k, r * k, Math.PI, 0, false)
        ctx.lineTo(x1 * k, bottom * k)
      }
      function outer() { ctx.beginPath(); arch(4.5, 19.5, 3.5, 18.5); ctx.closePath() }
      function inner() { ctx.beginPath(); arch(8, 16, 7.5, 18.5); arch(11, 13, 12, 18.5) }
      function half(right) { ctx.beginPath(); ctx.rect(right ? 12 * k : 0, 0, 12 * k, 24 * k); ctx.clip() }

      outer(); ctx.stroke()
      ctx.beginPath(); ctx.moveTo(2 * k, 21 * k); ctx.lineTo(22 * k, 21 * k); ctx.stroke()   // ground
      if (root.filled) {
        // Filled: the whole tunnel or (proxy) its left half, arches cut out
        ctx.save()
        if (root.half) half(false)
        outer(); ctx.fill()
        ctx.globalCompositeOperation = "destination-out"
        inner(); ctx.stroke()
        ctx.restore()
        if (root.half) { ctx.save(); half(true); inner(); ctx.stroke(); ctx.restore() }
      } else { inner(); ctx.stroke() }
    }

    onWidthChanged: canvas.requestPaint()
    onHeightChanged: canvas.requestPaint()
  }

  Connections {
    target: root
    function onColorChanged() { canvas.requestPaint() }
    function onFilledChanged() { canvas.requestPaint() }
    function onHalfChanged() { canvas.requestPaint() }
  }

  BorderSurface {
    visible: root.warning
    width: Math.max(7, parent.width * 0.42)
    height: width
    radius: width / 2
    color: root.badgeColor
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    borderSpec: Border.flat(Color.popups.background, 1)

    Text {
      anchors.centerIn: parent
      text: "!"
      color: Color.background
      font.family: Style.font.family
      font.pixelSize: Math.max(6, parent.height * 0.72)
      font.bold: true
    }
  }
}
