// ============================================================
//  PasswordBox.qml — Aurora Greeter
//  Qt6 drop-in replacement for SddmComponents.PasswordBox
//
//  SddmComponents API preserved:
//    property alias  text        – password text (r/w); onTextChanged works
//    property string font        – font family name string
//    property color  color       – background fill
//    property color  borderColor – idle border colour
//    property color  textColor   – masked text colour
//    property string tooltipBG   – kept for compat (not rendered as tooltip)
//    property string tooltipFG   – error indicator colour (default #dc322f)
//    property string image       – path to the warning icon
//
//  Extended properties:
//    property string errorText   – non-empty → warning icon appears
//                                  Add to Main.qml instantiation:
//                                    errorText: root.loginErrorText
//    property color  accentColor – bind to root.accentColor
//    property real   borderRadius
//
//  Design notes:
//    • No internal clear button — Main.qml's external clearPasswdButton
//      works as-is. Remove the external one and bind showClearButton: true
//      to enable the built-in version in a future refactor.
//    • Warning icon is non-interactive (enabled: false) and slides in
//      from opacity 0 → 1 with a 250 ms ease when login fails.
//    • Border turns to tooltipFG (red) on error; accent on focus.
// ============================================================

import QtQuick 2.15

FocusScope {
    id: root

    // ── SddmComponents-compatible API ────────────────────────
    property alias  text:        passwordField.text
    property string font:        "sans-serif"
    property color  color:       Qt.rgba(1, 1, 1, 0.08)
    property color  borderColor: "transparent"
    property color  textColor:   "white"
    property string tooltipBG:   "#25000000"
    property string tooltipFG:   "#dc322f"
    property string image:       ""

    // ── Extended: bind from Main.qml ──────────────────────────
    // errorText: root.loginErrorText     (drives warning icon)
    // accentColor: root.accentColor      (live accent from persist)
    property string errorText: ""

    property color accentColor: {
        if (typeof config !== "undefined" &&
                typeof config.accentColor !== "undefined" &&
                config.accentColor !== "")
            return config.accentColor
        return "#89b4fa"
    }

    property real borderRadius: {
        var v = (typeof config !== "undefined" &&
                 typeof config.borderRadius !== "undefined")
                ? parseFloat(config.borderRadius) : 8
        return isNaN(v) ? 8 : v
    }

    // ── DPI scaling ─────────────────────────────────────────────
    readonly property real _dpr: Screen.devicePixelRatio > 0
                                 ? Screen.devicePixelRatio : 1.0

    // ── Geometry ────────────────────────────────────────────────
    implicitWidth:  Math.round(280 * _dpr)
    implicitHeight: Math.round(36  * _dpr)

    // ── Derived state ────────────────────────────────────────────
    readonly property bool  _focused:    activeFocus || passwordField.activeFocus
    readonly property bool  _hasError:   errorText.length > 0
    readonly property color _errorColor: tooltipFG !== "" ? tooltipFG : "#dc322f"

    // Width of the warning icon slot (0 when hidden, with animation)
    readonly property real _iconSlot: _hasError && image !== ""
                                      ? Math.round(16 * _dpr) + Math.round(8 * _dpr)
                                      : 0

    // ── Glass background ─────────────────────────────────────────
    Rectangle {
        id: bg
        anchors.fill: parent
        radius: root.borderRadius
        color:  root.color

        // Three-state border: error (red) > focused (accent) > idle
        border.width: root._focused
                      ? Math.max(1, Math.round(1.5 * root._dpr))
                      : 1
        border.color: root._hasError ? root._errorColor
                     : root._focused  ? root.accentColor
                     :                  root.borderColor

        Behavior on border.color { ColorAnimation { duration: 200 } }
        Behavior on border.width { NumberAnimation { duration: 120 } }

        // Inner accent glow
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

        // Bottom concave shadow
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

    // ── Warning icon ─────────────────────────────────────────────
    // Floats at the left edge of the pill.  enabled: false ensures
    // it never captures mouse events from the password field below.
    Image {
        id: warningIcon
        anchors {
            left:           bg.left
            leftMargin:     Math.round(8 * root._dpr)
            verticalCenter: bg.verticalCenter
        }
        source:   root.image
        width:    Math.round(16 * root._dpr)
        height:   width
        fillMode: Image.PreserveAspectFit
        visible:  root._hasError && root.image !== ""
        enabled:  false   // non-blocking

        opacity: (root._hasError && root.image !== "") ? 1.0 : 0.0
        Behavior on opacity {
            NumberAnimation { duration: 250; easing.type: Easing.InOutQuad }
        }
    }

    // ── Animated left padding helper ──────────────────────────────
    // anchors.leftMargin cannot be targeted by Behavior directly in Qt6.
    // Use a plain property as the driver; anchor the Text and TextInput
    // to it so that Behavior can animate it.
    property real _leftPad: _iconSlot > 0
                            ? _iconSlot + Math.round(12 * _dpr)
                            : Math.round(12 * _dpr)
    Behavior on _leftPad { NumberAnimation { duration: 180; easing.type: Easing.InOutQuad } }

    // ── Placeholder text ─────────────────────────────────────────
    Text {
        anchors {
            left:           bg.left
            leftMargin:     root._leftPad
            verticalCenter: bg.verticalCenter
        }
        text:    "Password"
        visible: passwordField.text.length === 0 && !passwordField.activeFocus
        color:   Qt.rgba(1, 1, 1, 0.35)
        font {
            family:    root.font
            pixelSize: Math.round(14 * root._dpr)
        }
    }

    // ── Password input ───────────────────────────────────────────
    TextInput {
        id: passwordField
        anchors {
            left: bg.left
            right: bg.right
            leftMargin:  root._leftPad
            rightMargin: Math.round(12 * root._dpr)
            verticalCenter: bg.verticalCenter
        }

        focus:        true
        echoMode:     TextInput.Password
        clip:         true   // prevent bullets overflowing the pill on long passwords
        color:        root.textColor
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

        // Accent blinking cursor (identical timing to TextBox)
        cursorDelegate: Rectangle {
            width:  Math.round(2 * root._dpr)
            height: passwordField.cursorRectangle.height
            color:  root.accentColor
            radius: 1

            Behavior on color { ColorAnimation { duration: 300 } }

            SequentialAnimation on opacity {
                running: passwordField.activeFocus
                loops:   Animation.Infinite
                PauseAnimation  {                            duration: 380 }
                NumberAnimation { to: 0.0; duration: 480;
                                  easing.type: Easing.InOutSine }
                PauseAnimation  {                            duration: 80  }
                NumberAnimation { to: 1.0; duration: 380;
                                  easing.type: Easing.InOutSine }
            }
        }

        // Pass Tab / Backtab up for KeyNavigation handling
        Keys.onTabPressed:     function(event) { event.accepted = false }
        Keys.onBacktabPressed: function(event) { event.accepted = false }
    }

    // ── Focus delegation ─────────────────────────────────────────
    onActiveFocusChanged: {
        if (activeFocus) passwordField.forceActiveFocus()
    }
}
