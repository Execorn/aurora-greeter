// ============================================================
//  Button.qml — Aurora Greeter
//  Qt6 drop-in replacement for SddmComponents.Button
//
//  SddmComponents API preserved:
//    property string text          – button label / glyph
//    property string font          – font family name string
//    property color  color         – idle background (root Rectangle)
//    border.color                  – native Rectangle group property
//    border.width                  – native Rectangle group property
//    property color  textColor     – label colour
//    property color  activeColor   – hover fill colour
//    property color  pressedColor  – pressed fill colour
//    property color  disabledColor – disabled fill colour
//    signal  clicked()
//
//  Root type is Rectangle so border.color / border.width set by
//  the parent (Main.qml) work as native grouped properties without
//  any shim layer.
//
//  Hover animation strategy:
//    An internal bgFill Rectangle renders the animated colour on top
//    of root's own fill.  Since bgFill anchors.fill: parent (no gap),
//    it completely covers root's background fill.  Root's border is
//    painted AFTER both fills, so it always appears on top —
//    exactly the correct visual stacking order.
//    Root's `color` property remains unmodified and serves as the
//    idle target for bgFill's colour binding.
// ============================================================

import QtQuick 2.15

Rectangle {
    id: root

    // ── SddmComponents-compatible API ────────────────────────
    property string text:          ""
    property string font:          "sans-serif"
    property color  textColor:     "white"
    property color  activeColor:   "#268bd2"
    property color  pressedColor:  "#2aa198"
    property color  disabledColor: "#dc322f"

    // ── Signal ──────────────────────────────────────────────────
    signal clicked()

    // ── DPI scaling ─────────────────────────────────────────────
    readonly property real _dpr: Screen.devicePixelRatio > 0
                                 ? Screen.devicePixelRatio : 1.0

    // ── Geometry ────────────────────────────────────────────────
    implicitWidth:  Math.round(36 * _dpr)
    implicitHeight: Math.round(36 * _dpr)

    // ── Hover / press state ──────────────────────────────────────
    readonly property bool _hovered: hoverMa.containsMouse && root.enabled
    readonly property bool _pressed: hoverMa.pressed       && root.enabled

    // ── Animated fill layer ──────────────────────────────────────
    // Covers root's fill completely; animates between the four
    // state colours.  Root's native border.color/border.width draw
    // on top of this layer automatically (Rectangle paint order).
    Rectangle {
        id: bgFill
        anchors.fill: parent
        radius:       parent.radius

        color: {
            if (!root.enabled) return root.disabledColor
            if (root._pressed) return root.pressedColor
            if (root._hovered) return root.activeColor
            return root.color   // idle — reads parent-set colour directly
        }

        Behavior on color {
            ColorAnimation { duration: 160; easing.type: Easing.InOutQuad }
        }

        // Top-edge specular highlight — a 1 px white gradient strip
        // that catches the "light" and lifts the button off the surface.
        Rectangle {
            anchors {
                top:   parent.top
                left:  parent.left
                right: parent.right
            }
            height: 1
            radius: parent.radius
            color:  Qt.rgba(1, 1, 1,
                            root._pressed ? 0.04
                            : root._hovered ? 0.18
                            :                0.10)
            Behavior on color { ColorAnimation { duration: 140 } }
        }
    }

    // ── Label ────────────────────────────────────────────────────
    Text {
        id: label
        anchors.centerIn: parent
        text:             root.text
        color:            root.enabled
                          ? root.textColor
                          : Qt.rgba(root.textColor.r,
                                    root.textColor.g,
                                    root.textColor.b, 0.45)
        renderType:   Text.QtRendering
        antialiasing: true
        font {
            family:    root.font
            pixelSize: Math.round(14 * root._dpr)
        }

        // Subtle press-down scale for tactile feedback
        scale: root._pressed ? 0.90 : 1.0
        Behavior on scale {
            NumberAnimation { duration: 90; easing.type: Easing.OutBack }
        }
        Behavior on color { ColorAnimation { duration: 150 } }
    }

    // ── Interaction ───────────────────────────────────────────────
    MouseArea {
        id:           hoverMa
        anchors.fill: parent
        hoverEnabled: true
        cursorShape:  root.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked:    { if (root.enabled) root.clicked() }
    }
}
