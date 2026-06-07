// ============================================================
//  Clock.qml — Aurora Greeter
//  Qt6 drop-in replacement for SddmComponents.Clock
//
//  SddmComponents API preserved:
//    property color color      – text colour for both rows
//    property font  timeFont   – time font  (caller sets .family)
//    property font  dateFont   – date font  (caller sets .family)
//
//  Extended:
//    property string clockFormat – "24h" (default) or "12h"
//                                  Bind from Main.qml:
//                                    clockFormat: root.clockFormat
//
//  Layout:
//    ┌──────────────────────────────┐
//    │  22:45                       │  ← Font.Light, 64 sp, letter-spaced
//    │  Monday, June 2              │  ← Font.Light, 16 sp, tracked
//    └──────────────────────────────┘
//
//  The item sizes itself to its content (no fixed width/height).
//  Main.qml's centering arithmetic (clock.width / clock.height)
//  works correctly because root.width and root.height are
//  explicitly bound to the text items' implicit sizes.
//
//  Rendering:
//    Text.QtRendering — sub-pixel, resolution-independent antialiasing.
//    At 1440p (1.5× DPR) numerals render at effective 96 logical px,
//    which is fully crisp without any hinting artefacts.
//
//  Timer: 1000 ms interval.  _timeStr formats HH:mm / h:mm AP,
//  so it only emits a change signal once per minute.  The
//  Behavior on text for timeText fires ~60 × per hour (not every
//  second) — a subtle opacity crossfade on every minute change.
// ============================================================

import QtQuick 2.15

Item {
    id: root

    // ── SddmComponents-compatible API ────────────────────────
    property color color:    "white"
    property font  timeFont          // caller: timeFont.family: displayFont.name
    property font  dateFont          // caller: dateFont.family: displayFont.name

    // ── Extended: bind from Main.qml ──────────────────────────
    // clockFormat: root.clockFormat
    property string clockFormat: "24h"

    // ── DPI scaling ─────────────────────────────────────────────
    readonly property real _dpr: Screen.devicePixelRatio > 0
                                 ? Screen.devicePixelRatio : 1.0

    // ── Live time source ─────────────────────────────────────────
    // Reassigned every second; downstream bindings (_timeStr, _dateStr)
    // only re-evaluate when their output value actually changes.
    property var _now: new Date()

    Timer {
        interval: 1000
        running:  true
        repeat:   true
        onTriggered: root._now = new Date()
    }

    // ── Formatted strings ────────────────────────────────────────
    // "12h" → "3:45 PM"   (h:mm AP — no leading zero, uppercase AP)
    // "24h" → "15:45"     (HH:mm  — zero-padded 24-hour)
    readonly property string _timeStr:
        root.clockFormat === "12h"
        ? Qt.formatTime(root._now, "h:mm AP")
        : Qt.formatTime(root._now, "HH:mm")

    // Full weekday + month + day: "Monday, June 2"
    readonly property string _dateStr:
        Qt.formatDate(root._now, "dddd, MMMM d")

    // ── Self-sizing ───────────────────────────────────────────────
    // Bound to child implicit sizes — no circular dependency because
    // children use x/y (not anchors.top: parent.top) so their size
    // is computed independently from the parent's size.
    width:  Math.max(timeText.implicitWidth,
                     dateText.implicitWidth + Math.round(2 * _dpr))
    height: timeText.implicitHeight +
            Math.round(6 * _dpr) +
            dateText.implicitHeight

    // ── Time row ─────────────────────────────────────────────────
    Text {
        id: timeText
        x:  0
        y:  0

        text:         root._timeStr
        color:        root.color
        renderType:   Text.QtRendering   // sub-pixel antialiasing
        antialiasing: true
        textFormat:   Text.PlainText

        font {
            // Fall back gracefully if family isn't set yet during init
            family:        root.timeFont.family !== "" ? root.timeFont.family
                                                       : "sans-serif"
            pixelSize:     Math.round(64 * root._dpr)
            weight:        Font.Light       // 300 — elegant, airy numerals
            letterSpacing: -1.0            // tighten at large display sizes
        }

        // Subtle opacity crossfade when the minute flips.
        // SequentialAnimation: dim → swap text → brighten.
        // Fires roughly once per minute — not every second.
        Behavior on text {
            SequentialAnimation {
                NumberAnimation {
                    target:   timeText
                    property: "opacity"
                    to:       0.65
                    duration: 90
                    easing.type: Easing.InQuad
                }
                PropertyAction {}   // commits the new text string
                NumberAnimation {
                    target:   timeText
                    property: "opacity"
                    to:       1.0
                    duration: 120
                    easing.type: Easing.OutQuad
                }
            }
        }

        Behavior on color { ColorAnimation { duration: 300 } }
    }

    // ── Date row ─────────────────────────────────────────────────
    Text {
        id: dateText
        // Optical nudge: indent date by 2 logical pixels to align
        // with the numeral body (avoids flush-left clash with
        // numerals that have left side bearings).
        x: Math.round(2 * root._dpr)
        y: timeText.implicitHeight + Math.round(6 * root._dpr)

        text:         root._dateStr
        // Slightly dimmed — secondary information reads subordinate
        // to the time without being invisible against video backgrounds
        color:        Qt.rgba(root.color.r,
                              root.color.g,
                              root.color.b, 0.72)
        renderType:   Text.QtRendering
        antialiasing: true
        textFormat:   Text.PlainText

        font {
            family:        root.dateFont.family !== "" ? root.dateFont.family
                                                       : "sans-serif"
            pixelSize:     Math.round(16 * root._dpr)
            weight:        Font.Light
            letterSpacing: 0.8   // slight tracking improves legibility at small sizes
        }

        Behavior on color { ColorAnimation { duration: 300 } }
    }
}
