import QtQuick
import qs.Commons
import qs.Ui

/*
 * Vector shield-with-V mark drawn with Canvas primitives — no fonts, no SVG,
 * so it renders identically in tiny bar slots and in the panel hero.
 */
Item {
  id: root

  property real iconSize: Style.font.icon
  property color color: Color.foreground
  property bool warning: false
  // Connected state by shape, not hue: a solid shield with the V cut out
  // stays distinct in monochrome themes where "on" and "off" share a grey.
  property bool filled: false
  // proxy mode protects only apps that use the system proxy: half a shield
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
      var w = canvas.width
      var h = canvas.height
      var lw = Math.max(1.2, w * 0.075)

      ctx.lineWidth = lw
      ctx.strokeStyle = root.color
      ctx.lineJoin = "round"
      ctx.lineCap = "round"

      function shield() {
        ctx.beginPath()
        ctx.moveTo(0.16 * w, 0.18 * h)
        ctx.lineTo(0.84 * w, 0.18 * h)
        ctx.lineTo(0.84 * w, 0.46 * h)
        ctx.quadraticCurveTo(0.84 * w, 0.72 * h, 0.5 * w, 0.9 * h)
        ctx.quadraticCurveTo(0.16 * w, 0.72 * h, 0.16 * w, 0.46 * h)
        ctx.closePath()
      }
      function vee() {
        ctx.beginPath()
        ctx.moveTo(0.35 * w, 0.34 * h)
        ctx.lineTo(0.5 * w, 0.64 * h)
        ctx.lineTo(0.65 * w, 0.34 * h)
      }
      // the filled part: all of it, or the lower half
      function fillArea() {
        if (!root.half) return
        ctx.beginPath()
        ctx.rect(0, 0.5 * h, w, h)
        ctx.clip()
      }

      shield()
      ctx.stroke()
      if (root.filled) {
        ctx.save(); fillArea(); shield(); ctx.fillStyle = root.color; ctx.fill(); ctx.restore()
      }
      // the V: drawn on an empty shield, cut out of the fill; a half shield
      // keeps its upper half hollow so it reads as half even at bar size
      if (!root.filled) { vee(); ctx.stroke() }
      if (root.filled) {
        ctx.save(); fillArea(); ctx.globalCompositeOperation = "destination-out"; vee(); ctx.stroke(); ctx.restore()
      }
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
