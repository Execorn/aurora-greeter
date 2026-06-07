// ============================================================
//  TextBox.qml — Aurora Greeter
//  Qt6 drop-in replacement for SddmComponents.TextBox
//
//  SddmComponents API preserved:
//    property alias  text        – current value (r/w)
//    property string font        – font family name string
//    property color  color       – background fill
//    property color  borderColor – idle border colour
//    property color  textColor   – input text colour
//
//  Extended properties (bind from parent for live updates):
//    property color  accentColor  – bind to root.accentColor
//    property real   borderRadius – bind to root.borderRadius
//                                   (defaults to config.borderRadius)
//
//  Root is FocusScope so KeyNavigation and Keys.onPressed
//  set by Main.qml on the outer item work without modification.
// ============================================================

import QtQuick 2.15

FocusScope {
    id: root

    // ── SddmComponents-compatible API ────────────────────────
    property alias  text:        inputField.text
    property string font:        "sans-serif"
    property color  color:       Qt.rgba(1, 1, 1, 0.08)
    property color  borderColor: "transparent"
    property color  textColor:   "white"

    // ── Extended: bind from parent for live accent/radius ─────
    // Main.qml instantiation: accentColor: root.accentColor
    property color accentColor: {
        if (typeof config !== "undefined" &&
                typeof config.accentColor !== "undefined" &&
                config.accentColor !== "")
            return config.accentColor
        return "#89b4fa"
    }

    // Main.qml instantiation: borderRadius: parseFloat(config.borderRadius)
    property real borderRadius: {
        var v = (typeof config !== "undefined" &&
                 typeof config.borderRadius !== "undefined")
                ? parseFloat(config.borderRadius) : 8
        return isNaN(v) ? 8 : v
    }

    // ── DPI scaling ────────────────────────────────────────────
    // All pixel constants are multiplied by _dpr so the layout
    // is identical at 96 dpi (1×), 144 dpi (1.5×), 192 dpi (2×).
    readonly property real _dpr: Screen.devicePixelRatio > 0
                                 ? Screen.devicePixelRatio : 1.0

    // ── Geometry ────────────────────────────────────────────────
    implicitWidth:  Math.round(240 * _dpr)
    implicitHeight: Math.round(36  * _dpr)

    // ── Focus state ─────────────────────────────────────────────
    // True when either the FocusScope itself or its internal
    // TextInput holds active focus.
    readonly property bool _focused: activeFocus || inputField.activeFocus

    // ── Glass background ─────────────────────────────────────────
    Rectangle {
        id: bg
        anchors.fill: parent
        radius: root.borderRadius
        color:  root.color

        // Border: highlights with accentColor on focus.
        // Thickness increases slightly to make the ring more visible
        // on high-density displays.
        border.width: root._focused
                      ? Math.max(1, Math.round(1.5 * root._dpr))
                      : 1
        border.color: root._focused ? root.accentColor : root.borderColor

        Behavior on border.color { ColorAnimation { duration: 180 } }
        Behavior on border.width { NumberAnimation { duration: 120 } }

        // Secondary inner glow ring — adds depth on focus without
        // requiring QtGraphicalEffects or MultiEffect.
        Rectangle {
            anchors { fill: parent; margins: 2 }
            radius: Math.max(0, parent.radius - 2)
            color:  "transparent"
            border.color: root._focused
                          ? Qt.rgba(root.accentColor.r,
                                    root.accentColor.g,
                                    root.accentColor.b, 0.22)
                          : "transparent"
            border.width: 2
            Behavior on border.color { ColorAnimation { duration: 220 } }
        }

        // Subtle concave shadow at the bottom edge — sells depth
        Rectangle {
            anchors {
                bottom: parent.bottom
                left:   parent.left
                right:  parent.right
            }
            height: parent.height * 0.20
            radius: parent.radius
            gradient: Gradient {
                GradientStop { position: 0.0; color: "#00000000" }
                GradientStop { position: 1.0; color: "#16000000" }
            }
        }
    }

    // ── Placeholder text ─────────────────────────────────────────
    Text {
        anchors {
            left:           bg.left
            leftMargin:     Math.round(12 * root._dpr)
            verticalCenter: bg.verticalCenter
        }
        text:    "Username"
        visible: inputField.text.length === 0 && !inputField.activeFocus
        color:   Qt.rgba(1, 1, 1, 0.35)
        font {
            family:    root.font
            pixelSize: Math.round(14 * root._dpr)
        }
    }

    // ── Text input ───────────────────────────────────────────────
    TextInput {
        id: inputField
        anchors {
            left:           bg.left
            right:          bg.right
            leftMargin:     Math.round(12 * root._dpr)
            rightMargin:    Math.round(12 * root._dpr)
            verticalCenter: bg.verticalCenter
        }

        focus:        true
        clip:         true   // prevent typed text overflowing the pill at narrow widths
        color:        root.textColor
        // QtRendering gives sub-pixel antialiased glyphs on X11/Wayland,
        // producing razor-sharp text at 1440p and above.
        renderType:   Text.QtRendering
        antialiasing: true

        selectionColor:    Qt.rgba(root.accentColor.r,
                                   root.accentColor.g,
                                   root.accentColor.b, 0.40)
        selectedTextColor: root.textColor

        font {
            family:    root.font
            pixelSize: Math.round(14 * root._dpr)
        }

        // ── Accent blinking cursor ────────────────────────────
        // Custom cursorDelegate matches the accent colour and
        // uses a natural ease-in-out blink rather than a hard on/off.
        cursorDelegate: Rectangle {
            width:  Math.round(2 * root._dpr)
            height: inputField.cursorRectangle.height
            color:  root.accentColor
            radius: 1

            Behavior on color { ColorAnimation { duration: 300 } }

            SequentialAnimation on opacity {
                running: inputField.activeFocus
                loops:   Animation.Infinite
                PauseAnimation  {                            duration: 380 }
                NumberAnimation { to: 0.0; duration: 480;
                                  easing.type: Easing.InOutSine }
                PauseAnimation  {                            duration: 80  }
                NumberAnimation { to: 1.0; duration: 380;
                                  easing.type: Easing.InOutSine }
            }
        }

        // ── Tab / Backtab passthrough ─────────────────────────
        // Explicitly un-accept these so they propagate up to the
        // FocusScope, where Main.qml's KeyNavigation can act on them.
        // Without this, some Qt builds silently swallow Tab inside
        // TextInput, breaking the login→password focus cycle.
        Keys.onTabPressed:     function(event) { event.accepted = false }
        Keys.onBacktabPressed: function(event) { event.accepted = false }
    }

    // ── Focus delegation ─────────────────────────────────────────
    // When KeyNavigation moves focus to this FocusScope, route it
    // immediately into the TextInput so typing works without a
    // secondary click.
    onActiveFocusChanged: {
        if (activeFocus) inputField.forceActiveFocus()
    }
}
