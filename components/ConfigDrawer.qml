// ============================================================
//  ConfigDrawer.qml — Aurora Greeter
//  Qt6 / QtQuick 2.15 / QtQuick.Controls 2.15
//
//  A sliding glassmorphic configuration panel that mounts on
//  the left screen edge and exposes six live-updating control
//  sections:
//
//    1. Backdrop Style        — Video / Image / Slideshow / Color [NEW]
//    2. Wallpaper Playlist    — hot-swaps source per backdrop type
//    3. Slideshow Interval    — slider (5–60 s), only in slideshow [NEW]
//    4. Multi-Monitor Mode    — mirror / primary-only / blank-aux
//    5. Clock Format          — 24h / 12h pill toggle
//    6. Card Opacity          — styled Slider, live preview
//    7. Accent Colour         — 5 Catppuccin swatch presets
//
//  Public API (wired by Main.qml):
//    property QtObject settings          – the persist {} object
//    property var      reloadPlaylist    – Main.qml._reloadPlaylist  (video)
//    property var      reloadBackdrop    – Main.qml._reloadBackdrop  [NEW]
//    property Item     loginFocusTarget  – restored on drawer close
//
//  Public state interface:
//    property bool _open               – current open state
//    function toggle()                 – flip + route focus
//    function open()  / close()        – explicit setters
//
//  Design notes:
//    • The Backdrop Style control uses a four-segment pill button group
//      identical in structure to the monitor-mode selector, keeping a
//      consistent design language across all multi-choice controls.
//    • The Slideshow Interval section is wrapped in a height-animated
//      Item so it slides in and out smoothly when the mode changes,
//      avoiding the jarring layout jump that a visibility: false toggle
//      would create.
//    • Every settings write is followed by settings.sync() to flush
//      the JSON to disk immediately.
// ============================================================

import QtQuick 2.15
import QtQuick.Controls 2.15

// The outermost Item is NOT clipped so the gear tab handle can
// protrude outside the drawer's width boundary when closed.
Item {
    id: root

    // ─────────────────────────────────────────────────────────────
    //  PUBLIC API  (wired by Main.qml)
    // ─────────────────────────────────────────────────────────────

    // The live persist {} QtObject from Main.qml.
    property QtObject settings:         null

    // Reference to Main.qml._reloadPlaylist(resolvedUrl).
    // Used for video-mode playlist changes.
    property var      reloadPlaylist:   null

    // [NEW] Reference to Main.qml._reloadBackdrop(type, resolvedUrl).
    // Used for all mode switches and backdrop source changes.
    property var      reloadBackdrop:   null

    // [v5] Callback to refresh backdrop after changing schedule settings.
    property var      updateBackdropFromSettings: null

    // The item that receives focus when the drawer closes.
    property Item     loginFocusTarget: null

    // ─────────────────────────────────────────────────────────────
    //  STATE MACHINE
    // ─────────────────────────────────────────────────────────────

    property bool _open: false

    function toggle() {
        _open = !_open
        if (_open) {
            drawerScope.forceActiveFocus()
            // Re-read the catalogue every time the drawer opens so CLI-added
            // playlists appear without needing a full theme restart.
            _loadCatalogue()
        } else if (loginFocusTarget !== null) {
            loginFocusTarget.forceActiveFocus()
        }
    }

    function open() {
        _open = true
        drawerScope.forceActiveFocus()
    }

    function close() {
        _open = false
        if (loginFocusTarget !== null)
            loginFocusTarget.forceActiveFocus()
    }

    // ─────────────────────────────────────────────────────────────
    //  GEOMETRY
    // ─────────────────────────────────────────────────────────────

    readonly property int _panelWidth: 340
    readonly property int _tabWidth:   36
    readonly property int _tabHeight:  52

    width:  _open ? _panelWidth + _tabWidth : _tabWidth

    // ─────────────────────────────────────────────────────────────
    //  THEME TOKEN HELPERS
    // ─────────────────────────────────────────────────────────────

    readonly property real _radius: {
        var v = (typeof config !== "undefined" &&
                 typeof config.borderRadius !== "undefined")
                ? parseFloat(config.borderRadius) : 12
        return isNaN(v) ? 12 : v
    }

    readonly property color _borderColor: {
        if (typeof config !== "undefined" &&
                typeof config.borderColor !== "undefined" &&
                config.borderColor !== "")
            return config.borderColor
        return "#40FFFFFF"
    }

    // _accent re-evaluates whenever settings.accentColor changes.
    readonly property color _accent: {
        if (settings !== null &&
                typeof settings.accentColor === "string" &&
                settings.accentColor !== "")
            return settings.accentColor
        return "#89b4fa"
    }

    // ─────────────────────────────────────────────────────────────
    //  DATA MODELS
    // ─────────────────────────────────────────────────────────────

    // ────────────────────────────────────────────────────────────
    //  DYNAMIC CATALOGUE MODELS
    //
    //  Populated at startup and on each drawer open from:
    //    {THEME_ROOT}/playlists/index.json
    //
    //  index.json format:
    //    {
    //      "version": 1,
    //      "video": [ { "label": "All Videos", "path": "playlists/Background.mp4", "default": true } ],
    //      "image": [ { "label": "Default Image", "path": "backgrounds/background.jpg", "default": true } ]
    //    }
    //
    //  The CLI (sddm-aurora-ctl) appends to this file when the user adds
    //  a new folder playlist or image source.
    // ────────────────────────────────────────────────────────────

    // Separate models for video playlists and image sources
    ListModel { id: videoPlaylistModel }
    ListModel { id: imageSourceModel }

    property bool _catalogueLoaded: false

    // Resolve the active model for the current backdrop type.
    // video            → videoPlaylistModel
    // image / slideshow → imageSourceModel
    readonly property var _activeSourceModel: {
        switch (_backdropType) {
            case "image":     return imageSourceModel
            case "slideshow": return imageSourceModel   // slideshow cycles through images
            default:          return videoPlaylistModel  // "video"
        }
    }

    // ────────────────────────────────────────────────────────────
    //  _loadCatalogue()
    //
    //  Reads index.json and populates videoPlaylistModel / imageSourceModel.
    //  Falls back to hardcoded defaults if the file is missing or malformed.
    //  ConfigDrawer lives in components/ so index.json is at ../playlists/index.json
    //  relative to this file's location.
    // ────────────────────────────────────────────────────────────
    function _loadCatalogue() {
        var indexUrl = Qt.resolvedUrl("../playlists/index.json")
        var xhr = new XMLHttpRequest()
        xhr.open("GET", indexUrl, false /* synchronous */)
        try {
            xhr.send()
        } catch(e) {
            console.warn("[Aurora] ConfigDrawer: failed to load catalogue:", e)
            _populateCatalogueDefaults()
            return
        }

        if (xhr.status !== 0 && xhr.status !== 200) {
            console.warn("[Aurora] ConfigDrawer: catalogue HTTP error:", xhr.status)
            _populateCatalogueDefaults()
            return
        }

        if (!xhr.responseText || xhr.responseText.trim() === "") {
            console.warn("[Aurora] ConfigDrawer: catalogue file empty")
            _populateCatalogueDefaults()
            return
        }

        try {
            var data = JSON.parse(xhr.responseText)

            videoPlaylistModel.clear()
            imageSourceModel.clear()

            if (Array.isArray(data.video)) {
                for (var i = 0; i < data.video.length; i++) {
                    var ve = data.video[i]
                    if (typeof ve.label === "string" && typeof ve.path === "string")
                        videoPlaylistModel.append({ label: ve.label, path: ve.path })
                }
            }

            if (Array.isArray(data.image)) {
                for (var j = 0; j < data.image.length; j++) {
                    var ie = data.image[j]
                    if (typeof ie.label === "string" && typeof ie.path === "string")
                        imageSourceModel.append({ label: ie.label, path: ie.path })
                }
            }

            // If the file was parseable but sections were missing, fill defaults
            if (videoPlaylistModel.count === 0)
                videoPlaylistModel.append({ label: "All Videos", path: "playlists/Background.mp4" })
            if (imageSourceModel.count === 0)
                imageSourceModel.append({ label: "Default Image", path: "backgrounds/background.jpg" })

            _catalogueLoaded = true
            console.log("[Aurora] Catalogue loaded:",
                        videoPlaylistModel.count, "video entries,",
                        imageSourceModel.count, "image entries")

        } catch(e) {
            console.warn("[Aurora] ConfigDrawer: catalogue JSON parse error:", e)
            _populateCatalogueDefaults()
        }
    }

    function _populateCatalogueDefaults() {
        videoPlaylistModel.clear()
        imageSourceModel.clear()
        videoPlaylistModel.append({ label: "All Videos",     path: "playlists/Background.mp4"   })
        imageSourceModel.append(  { label: "Default Image",  path: "backgrounds/background.jpg" })
        _catalogueLoaded = true
        console.log("[Aurora] Catalogue: using built-in defaults")
    }

    Component.onCompleted: {
        _loadCatalogue()
    }

    ListModel {
        id: accentModel
        ListElement { label: "Lavender"; hex: "#b4befe" }
        ListElement { label: "Sapphire"; hex: "#74c7ec" }
        ListElement { label: "Mauve";    hex: "#cba6f7" }
        ListElement { label: "Teal";     hex: "#94e2d5" }
        ListElement { label: "Peach";    hex: "#fab387" }
    }

    // Backdrop type definitions
    readonly property var _backdropModes: [
        { label: "Video",     value: "video"     },
        { label: "Image",     value: "image"     },
        { label: "Slideshow", value: "slideshow" },
        { label: "Color",     value: "color"     }
    ]

    readonly property var _monitorModes: [
        { label: "Primary Only", value: "primary-only"    },
        { label: "Mirror",       value: "mirror"          },
        { label: "Blank Aux",    value: "blank-auxiliary" }
    ]

    // Current backdrop type shorthand (null-guarded)
    readonly property string _backdropType:
        (settings !== null && typeof settings.activeBackgroundType === "string")
        ? settings.activeBackgroundType : "video"


    // ─────────────────────────────────────────────────────────────
    //  FOCUSSCOPE WRAPPER — clips the sliding panel content only.
    // ─────────────────────────────────────────────────────────────
    FocusScope {
        id: drawerScope

        anchors {
            top:    parent.top
            left:   parent.left
            bottom: parent.bottom
        }

        width:   root._open ? root._panelWidth : 0
        opacity: root._open ? 0.95 : 0.0
        clip:    true

        Behavior on width   { NumberAnimation { duration: 350; easing.type: Easing.OutCubic } }
        Behavior on opacity { NumberAnimation { duration: 350; easing.type: Easing.OutCubic } }

        Keys.onEscapePressed: function(event) {
            root.close()
            event.accepted = true
        }

        // ─────────────────────────────────────────────────────────
        //  GLASSMORPHIC BACKGROUND PANEL
        // ─────────────────────────────────────────────────────────
        Rectangle {
            id: glassPanel
            x:      -root._radius
            y:      0
            width:  parent.width + root._radius
            height: parent.height
            radius: root._radius

            color: {
                if (typeof config !== "undefined" &&
                        typeof config.loginCardColor !== "undefined" &&
                        config.loginCardColor !== "")
                    return config.loginCardColor
                return "#1A101828"
            }

            border.color: root._borderColor
            border.width: 1

            layer.enabled: true
            layer.smooth:  true

            // Subtle specular gradient
            Rectangle {
                anchors.fill: parent
                radius:       parent.radius
                gradient: Gradient {
                    GradientStop { position: 0.00; color: "#22FFFFFF" }
                    GradientStop { position: 0.30; color: "#08FFFFFF" }
                    GradientStop { position: 1.00; color: "#05000000" }
                }
            }

            // Accent-coloured glow stripe on the right edge
            Rectangle {
                anchors { top: parent.top; right: parent.right; bottom: parent.bottom }
                width:  2
                radius: 1
                color:  Qt.rgba(root._accent.r, root._accent.g, root._accent.b, 0.55)
                Behavior on color { ColorAnimation { duration: 400 } }
            }
        }

        // ─────────────────────────────────────────────────────────
        //  SCROLLABLE CONTENT
        // ─────────────────────────────────────────────────────────
        ScrollView {
            anchors.fill: parent
            clip:         true

            ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

            ScrollBar.vertical: ScrollBar {
                policy: ScrollBar.AsNeeded
                width:  4
                contentItem: Rectangle {
                    implicitWidth:  4
                    implicitHeight: 40
                    radius: 2
                    color:  Qt.rgba(1, 1, 1, 0.28)
                }
                background: Rectangle { color: "transparent" }
            }

            Column {
                id: contentColumn
                width:   root._panelWidth
                spacing: 0

                // ─────────────────────────────────────────────────
                //  HEADER — title + close button
                // ─────────────────────────────────────────────────
                Item {
                    width:  parent.width
                    height: 62

                    Text {
                        anchors {
                            left:           parent.left
                            leftMargin:     18
                            verticalCenter: parent.verticalCenter
                        }
                        text:  "Theme Settings"
                        color: "white"
                        font { pixelSize: 14; bold: true; family: "sans-serif" }
                    }

                    Rectangle {
                        anchors {
                            right:          parent.right
                            rightMargin:    12
                            verticalCenter: parent.verticalCenter
                        }
                        width:  28; height: 28; radius: 14
                        color: xMa.containsMouse
                               ? Qt.rgba(1, 1, 1, 0.14) : "transparent"
                        Behavior on color { ColorAnimation { duration: 120 } }

                        Text {
                            anchors.centerIn: parent
                            text:  "✕"
                            color: Qt.rgba(1, 1, 1, 0.65)
                            font { pixelSize: 12; family: "sans-serif" }
                        }
                        MouseArea {
                            id: xMa; anchors.fill: parent
                            hoverEnabled: true
                            cursorShape:  Qt.PointingHandCursor
                            onClicked:    root.close()
                        }
                    }

                    Rectangle {
                        anchors { bottom: parent.bottom; left: parent.left; right: parent.right }
                        height: 1; color: Qt.rgba(1, 1, 1, 0.09)
                    }
                }

                // ─────────────────────────────────────────────────
                //  SECTION: PERFORMANCE PROFILE             [NEW v4]
                //
                //  Three-segment pill button group.
                //  Segments map to performanceMode values:
                //
                //    Low  — Force 2K video URLs regardless of screen size;
                //           reduced animation durations (less GPU compositing).
                //           Best for integrated graphics / CPU-only decode.
                //
                //    Auto — Adaptive: screen ≤ 1920 px wide → 2K URLs;
                //           wider screens → playlist URLs unchanged.
                //           Animation durations stay at "high" values.
                //           Default for most users.
                //
                //    High — Always use playlist URLs as-is (may be 4K);
                //           full cinematic animation durations.
                //           Best for dedicated GPU with hardware decode.
                //
                //  On change:
                //    1. Writes settings.performanceMode.
                //    2. Re-triggers _reloadBackdrop so the active playlist
                //       is re-parsed with the new resolution cap.
                //    3. Flushes settings to disk via settings.sync().
                // ─────────────────────────────────────────────────
                SectionLabel { label: "PERFORMANCE" }

                Item {
                    width:  parent.width
                    height: 58

                    // Three-column description row beneath the pill
                    readonly property var _perfDescriptions: [
                        "Integrated GPU / CPU decode\n2K video, fast animations",
                        "Screen-adaptive quality\nAuto 2K / 4K by resolution",
                        "Dedicated GPU / HW decode\n4K video, cinematic fades"
                    ]

                    Rectangle {
                        id: perfContainer
                        anchors {
                            left:           parent.left
                            right:          parent.right
                            leftMargin:     16
                            rightMargin:    16
                            verticalCenter: parent.verticalCenter
                        }
                        height:       34
                        radius:       8
                        clip:         true
                        color:        Qt.rgba(1, 1, 1, 0.04)
                        border.color: Qt.rgba(1, 1, 1, 0.13)
                        border.width: 1

                        readonly property var _perfModes: [
                            { label: "Low",  value: "low"  },
                            { label: "Auto", value: "auto" },
                            { label: "High", value: "high" }
                        ]

                        Row {
                            anchors.fill: parent

                            Repeater {
                                model: perfContainer._perfModes

                                Rectangle {
                                    width:  perfContainer.width / perfContainer._perfModes.length
                                    height: perfContainer.height

                                    readonly property bool _sel: {
                                        if (root.settings === null) return modelData.value === "auto"
                                        return root.settings.performanceMode === modelData.value
                                    }

                                    // Colour coding per mode:
                                    //   low  → warm amber tint  (⚠ performance warning colour)
                                    //   auto → accent colour    (neutral default)
                                    //   high → green tint       (✓ best quality)
                                    readonly property color _modeAccent: {
                                        switch (modelData.value) {
                                            case "low":  return Qt.rgba(0.97, 0.68, 0.30, 1) // amber
                                            case "high": return Qt.rgba(0.55, 0.85, 0.55, 1) // green
                                            default:     return root._accent
                                        }
                                    }

                                    color: _sel
                                           ? Qt.rgba(_modeAccent.r, _modeAccent.g, _modeAccent.b, 0.25)
                                           : (perfMa.containsMouse ? Qt.rgba(1, 1, 1, 0.09) : "transparent")
                                    Behavior on color { ColorAnimation { duration: 130 } }

                                    // Vertical divider (skip last segment)
                                    Rectangle {
                                        anchors { right: parent.right; top: parent.top; bottom: parent.bottom }
                                        width:   1
                                        visible: index < perfContainer._perfModes.length - 1
                                        color:   Qt.rgba(1, 1, 1, 0.12)
                                    }

                                    Text {
                                        anchors.centerIn: parent
                                        text:  modelData.label
                                        color: parent._sel ? parent._modeAccent : Qt.rgba(1, 1, 1, 0.62)
                                        font { pixelSize: 11; bold: parent._sel; family: "sans-serif" }
                                        Behavior on color { ColorAnimation { duration: 130 } }
                                    }

                                    MouseArea {
                                        id:           perfMa
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape:  Qt.PointingHandCursor
                                        onClicked: {
                                            if (root.settings === null) return
                                            root.settings.performanceMode = modelData.value
                                            root.settings.sync()
                                            // Re-trigger the pipeline so the new
                                            // resolution cap takes effect immediately.
                                            // Pass raw path strings — Main.qml's _reloadBackdrop
                                            // uses Qt.resolvedUrl() in the Main.qml context
                                            // (theme root), not the components/ subdir.
                                            if (typeof root.reloadBackdrop === "function") {
                                                var t = root.settings.activeBackgroundType
                                                var s = (t === "video")
                                                        ? root.settings.activePlaylist
                                                        : root.settings.activeMediaSource
                                                root.reloadBackdrop(t, s)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // Hint text beneath the performance selector —
                // shows a one-line description of the active mode
                Item {
                    width:  parent.width
                    height: 32

                    Text {
                        anchors {
                            left:           parent.left
                            leftMargin:     18
                            right:          parent.right
                            rightMargin:    18
                            verticalCenter: parent.verticalCenter
                        }
                        text: {
                            if (root.settings === null) return "Adaptive quality"
                            switch (root.settings.performanceMode) {
                                case "low":  return "\u26a0 2K video · fast animations · best for iGPU/CPU decode"
                                case "high": return "\u2713 Full quality · cinematic fades · requires HW decode"
                                default:     return "\u2022 Screen-adaptive: ≤ 1920px wide \u2192 2K · wider \u2192 4K"
                            }
                        }
                        color:    Qt.rgba(1, 1, 1, 0.38)
                        font { pixelSize: 9; family: "sans-serif" }
                        wrapMode: Text.WordWrap
                    }
                }

                SectionDivider {}

                // ─────────────────────────────────────────────────
                //  SECTION: BACKDROP STYLE
                //
                //  Four-segment pill button group.  Each segment
                //  maps to one activeBackgroundType value.
                //  Selecting a segment:
                //    1. Writes settings.activeBackgroundType.
                //    2. Calls reloadBackdrop(type, currentPlaylistUrl)
                //       so the live pipeline switches immediately.
                //    3. Calls settings.sync() to flush to disk.
                // ─────────────────────────────────────────────────
                SectionLabel { label: "BACKDROP STYLE" }

                Item {
                    width:  parent.width
                    height: 58

                    Rectangle {
                        id: backdropContainer
                        anchors {
                            left:           parent.left
                            right:          parent.right
                            leftMargin:     16
                            rightMargin:    16
                            verticalCenter: parent.verticalCenter
                        }
                        height:       34
                        radius:       8
                        clip:         true
                        color:        Qt.rgba(1, 1, 1, 0.04)
                        border.color: Qt.rgba(1, 1, 1, 0.13)
                        border.width: 1

                        Row {
                            anchors.fill: parent

                            Repeater {
                                model: root._backdropModes

                                Rectangle {
                                    width:  backdropContainer.width / root._backdropModes.length
                                    height: backdropContainer.height

                                    readonly property bool _sel:
                                        root._backdropType === modelData.value

                                    color: _sel
                                           ? Qt.rgba(root._accent.r, root._accent.g, root._accent.b, 0.28)
                                           : (bdMa.containsMouse ? Qt.rgba(1, 1, 1, 0.09) : "transparent")
                                    Behavior on color { ColorAnimation { duration: 130 } }

                                    // Vertical divider (skip last segment)
                                    Rectangle {
                                        anchors { right: parent.right; top: parent.top; bottom: parent.bottom }
                                        width:   1
                                        visible: index < root._backdropModes.length - 1
                                        color:   Qt.rgba(1, 1, 1, 0.12)
                                    }

                                    Text {
                                        anchors.centerIn: parent
                                        text:  modelData.label
                                        color: parent._sel ? root._accent : Qt.rgba(1, 1, 1, 0.62)
                                        font { pixelSize: 11; bold: parent._sel; family: "sans-serif" }
                                        Behavior on color { ColorAnimation { duration: 130 } }
                                    }

                                    MouseArea {
                                        id:           bdMa
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape:  Qt.PointingHandCursor
                                        onClicked: {
                                            if (root.settings === null) return
                                            var newType = modelData.value
                                            root.settings.activeBackgroundType = newType
                                            root.settings.sync()

                                            // Hot-swap the live pipeline.
                                            // CRITICAL: never pass a video M3U to image/slideshow
                                            // modes — Image{} cannot render .mov and the
                                            // onStatusChanged guard would never set opacity=1.
                                            // Pass raw path strings (not Qt.resolvedUrl) so that
                                            // Main.qml resolves them against the theme root, not
                                            // the components/ subdirectory.
                                            if (root.settings.useDayNightSchedule) {
                                                if (typeof root.updateBackdropFromSettings === "function") {
                                                    root.updateBackdropFromSettings()
                                                }
                                            } else {
                                                if (typeof root.reloadBackdrop === "function") {
                                                    var srcPath = (newType === "video")
                                                        ? root.settings.activePlaylist
                                                        : root.settings.activeMediaSource
                                                    root.reloadBackdrop(newType, srcPath)
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                SectionDivider {}

                // ─────────────────────────────────────────────────
                //  SECTION: DAY/NIGHT SCHEDULING
                // ─────────────────────────────────────────────────
                SectionLabel { label: "DAY/NIGHT SCHEDULING" }

                Item {
                    width:  parent.width
                    height: 58

                    Rectangle {
                        id: scheduleTrack
                        anchors {
                            left:           parent.left
                            right:          parent.right
                            leftMargin:     16
                            rightMargin:    16
                            verticalCenter: parent.verticalCenter
                        }
                        height:       36
                        radius:       18
                        color:        Qt.rgba(1, 1, 1, 0.06)
                        border.color: Qt.rgba(1, 1, 1, 0.13)
                        border.width: 1

                        readonly property bool _isScheduled:
                            root.settings !== null && root.settings.useDayNightSchedule

                        Rectangle {
                            id: scheduleThumb
                            width:  scheduleTrack.width / 2 - 4
                            height: scheduleTrack.height - 6
                            y:      3
                            x:      scheduleTrack._isScheduled ? 3 : scheduleTrack.width / 2 + 1
                            radius: height / 2
                            color:  Qt.rgba(root._accent.r, root._accent.g, root._accent.b, 0.82)

                            Behavior on x     { NumberAnimation { duration: 220; easing.type: Easing.InOutCubic } }
                            Behavior on color { ColorAnimation  { duration: 400 } }
                        }

                        Text {
                            width:               parent.width / 2
                            height:              parent.height
                            text:                "Scheduled"
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment:   Text.AlignVCenter
                            color: scheduleTrack._isScheduled ? "white" : Qt.rgba(1, 1, 1, 0.40)
                            font { pixelSize: 13; bold: scheduleTrack._isScheduled; family: "sans-serif" }
                            Behavior on color { ColorAnimation { duration: 200 } }
                        }

                        Text {
                            x:                   parent.width / 2
                            width:               parent.width / 2
                            height:              parent.height
                            text:                "Manual"
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment:   Text.AlignVCenter
                            color: !scheduleTrack._isScheduled ? "white" : Qt.rgba(1, 1, 1, 0.40)
                            font { pixelSize: 13; bold: !scheduleTrack._isScheduled; family: "sans-serif" }
                            Behavior on color { ColorAnimation { duration: 200 } }
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape:  Qt.PointingHandCursor
                            onClicked: {
                                if (root.settings === null) return
                                root.settings.useDayNightSchedule = !scheduleTrack._isScheduled
                                root.settings.sync()
                                if (typeof root.updateBackdropFromSettings === "function") {
                                    root.updateBackdropFromSettings()
                                }
                            }
                        }
                    }
                }

                SectionDivider {}

                // ─────────────────────────────────────────────────
                //  SECTION: WALLPAPER / IMAGE SOURCE
                //
                //  Playlist rows are shown in all modes.  The label
                //  and behaviour adapt based on activeBackgroundType:
                //    • "video"     → hot-swaps the video playlist
                //    • "image"     → sets the static image source
                //    • "slideshow" → sets the image slideshow playlist
                //    • "color"     → rows are dimmed (not applicable)
                // ─────────────────────────────────────────────────
                SectionLabel {
                    label: {
                        switch (root._backdropType) {
                            case "video":     return "VIDEO PLAYLIST"
                            case "image":     return "STATIC IMAGE"
                            case "slideshow": return "SLIDESHOW PLAYLIST"
                            case "color":     return "BACKGROUND COLOR"
                            default:          return "SOURCE"
                        }
                    }
                }

                // ── Color-mode solid picker (only shown in "color" mode) ──
                //    A simple row of preset swatches for the solid background.
                //    Tapping a swatch writes backgroundColor and calls reloadBackdrop.
                Item {
                    width:  parent.width
                    // Animate height so the row slides in/out smoothly
                    height: root._backdropType === "color" ? 68 : 0
                    clip:   true

                    Behavior on height { NumberAnimation { duration: 220; easing.type: Easing.InOutCubic } }

                    // Visible only in color mode; height animation handles the rest
                    visible: height > 0

                    readonly property var _colorPresets: [
                        { label: "Midnight",  hex: "#1e1e2e" },
                        { label: "Onyx",      hex: "#0d0d0d" },
                        { label: "Deep Navy", hex: "#0a1628" },
                        { label: "Plum",      hex: "#1a0a2e" },
                        { label: "Forest",    hex: "#0a1a0e" }
                    ]

                    Row {
                        anchors {
                            left:           parent.left
                            right:          parent.right
                            leftMargin:     16
                            rightMargin:    16
                            verticalCenter: parent.verticalCenter
                        }

                        Repeater {
                            model: parent.parent._colorPresets

                            Item {
                                width:  (contentColumn.width - 32) / parent.parent._colorPresets.length
                                height: 58

                                readonly property bool _sel:
                                    root.settings !== null &&
                                    root.settings.backgroundColor === modelData.hex

                                Rectangle {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    anchors.top:              parent.top
                                    anchors.topMargin:        6
                                    width:  parent._sel ? 44 : 34
                                    height: width; radius: width / 2
                                    color:  "transparent"
                                    border.color: parent._sel ? modelData.hex : Qt.rgba(1, 1, 1, 0.0)
                                    border.width: 2
                                    opacity: 0.72
                                    Behavior on width        { NumberAnimation { duration: 180 } }
                                    Behavior on border.color { ColorAnimation  { duration: 200 } }
                                }

                                Rectangle {
                                    id: colorSwatch
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    anchors.top:              parent.top
                                    anchors.topMargin:        10
                                    width:  parent._sel ? 32 : 24
                                    height: width; radius: width / 2
                                    color:  modelData.hex
                                    border.color: Qt.rgba(1, 1, 1, 0.2)
                                    border.width: 1

                                    Behavior on width {
                                        NumberAnimation { duration: 180; easing.type: Easing.OutBack }
                                    }

                                    scale: colorSwMa.containsMouse ? 1.12 : 1.0
                                    Behavior on scale {
                                        NumberAnimation { duration: 120; easing.type: Easing.OutBack }
                                    }

                                    Text {
                                        anchors.centerIn: parent
                                        visible:  parent.parent._sel
                                        text:     "✓"
                                        color:    Qt.rgba(1, 1, 1, 0.85)
                                        font { pixelSize: 11; bold: true; family: "sans-serif" }
                                    }
                                }

                                Text {
                                    anchors {
                                        top:              colorSwatch.bottom
                                        topMargin:        4
                                        horizontalCenter: parent.horizontalCenter
                                    }
                                    text:  modelData.label
                                    color: parent._sel ? modelData.hex : Qt.rgba(1, 1, 1, 0.32)
                                    font { pixelSize: 9; family: "sans-serif" }
                                    Behavior on color { ColorAnimation { duration: 200 } }
                                }

                                MouseArea {
                                    id:           colorSwMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape:  Qt.PointingHandCursor
                                    onClicked: {
                                        if (root.settings === null) return
                                        root.settings.backgroundColor = modelData.hex
                                        root.settings.sync()
                                        // reloadBackdrop handles live update (color mode
                                        // only needs the persist property change — the
                                        // binding on solidBlack.color does the rest)
                                        if (typeof root.reloadBackdrop === "function")
                                            root.reloadBackdrop("color", "")
                                    }
                                }
                            }
                        }
                    }
                }

                // ── Playlist rows (video / image / slideshow) ──────────────────
                Repeater {
                    model: root._activeSourceModel

                    delegate: Rectangle {
                        id: plRow
                        width:  contentColumn.width
                        height: root._backdropType !== "color" ? 46 : 0
                        clip:   true

                        Behavior on height { NumberAnimation { duration: 180; easing.type: Easing.InOutCubic } }

                        visible: height > 0

                        // _active is mode-aware:
                        //   video mode      → compare against activePlaylist
                        //   image/slideshow → compare against activeMediaSource
                        readonly property bool _active: {
                            if (root.settings === null || root.settings.useDayNightSchedule) return false
                            if (root._backdropType === "video")
                                return root.settings.activePlaylist    === model.path
                            return root.settings.activeMediaSource === model.path
                        }

                        color: _active
                               ? Qt.rgba(root._accent.r, root._accent.g, root._accent.b, 0.16)
                               : (plMa.containsMouse ? Qt.rgba(1, 1, 1, 0.06) : "transparent")
                        Behavior on color { ColorAnimation { duration: 130 } }

                        // Left accent bar — visible on active row only
                        Rectangle {
                            anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
                            width:  3; radius: 1.5
                            color:  plRow._active ? root._accent : "transparent"
                            Behavior on color { ColorAnimation { duration: 200 } }
                        }

                        // State icon: ▶ playing, ◦ idle
                        Text {
                            id: plIcon
                            anchors {
                                left:           parent.left
                                leftMargin:     18
                                verticalCenter: parent.verticalCenter
                            }
                            text:  plRow._active ? "▶" : "◦"
                            color: plRow._active ? root._accent : Qt.rgba(1, 1, 1, 0.28)
                            font { pixelSize: 10; family: "sans-serif" }
                            Behavior on color { ColorAnimation { duration: 200 } }
                        }

                        Text {
                            anchors {
                                left:           plIcon.right
                                leftMargin:     10
                                verticalCenter: parent.verticalCenter
                            }
                            text:  model.label
                            color: plRow._active ? "white" : Qt.rgba(1, 1, 1, 0.68)
                            font { pixelSize: 13; bold: plRow._active; family: "sans-serif" }
                            Behavior on color { ColorAnimation { duration: 150 } }
                        }

                        // "LIVE" pill badge — active entry only
                        Rectangle {
                            anchors {
                                right:          parent.right
                                rightMargin:    14
                                verticalCenter: parent.verticalCenter
                            }
                            visible:      plRow._active
                            width:        38; height: 18; radius: 9
                            color:        Qt.rgba(root._accent.r, root._accent.g, root._accent.b, 0.22)
                            border.color: Qt.rgba(root._accent.r, root._accent.g, root._accent.b, 0.55)
                            border.width: 1

                            Text {
                                anchors.centerIn: parent
                                text:  "LIVE"
                                color: root._accent
                                font { pixelSize: 9; bold: true; letterSpacing: 0.8; family: "sans-serif" }
                            }
                        }

                        // Inter-row hairline
                        Rectangle {
                            anchors { bottom: parent.bottom; left: parent.left; right: parent.right }
                            height:  1
                            visible: index < root._activeSourceModel.count - 1
                            color:   Qt.rgba(1, 1, 1, 0.05)
                        }

                        MouseArea {
                            id:           plMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape:  Qt.PointingHandCursor

                            onClicked: {
                                if (root.settings === null) return

                                var type = root._backdropType

                                // Write to the correct settings key based on mode.
                                root.settings.useDayNightSchedule = false
                                if (type === "video") {
                                    root.settings.activePlaylist = model.path
                                } else {
                                    root.settings.activeMediaSource = model.path
                                }
                                root.settings.sync()

                                // Hot-swap the live pipeline.
                                // Pass model.path as a raw string — Main.qml resolves
                                // it against the theme root, not components/.
                                if (type === "video") {
                                    if (typeof root.reloadPlaylist === "function")
                                        root.reloadPlaylist(model.path)
                                } else {
                                    if (typeof root.reloadBackdrop === "function")
                                        root.reloadBackdrop(type, model.path)
                                }
                            }
                        }
                    }
                }

                SectionDivider {}

                // ─────────────────────────────────────────────────
                //  SECTION: SLIDESHOW INTERVAL               [NEW]
                //
                //  Only revealed when activeBackgroundType === "slideshow".
                //  Height animates from 0 to its full value so the
                //  layout shifts smoothly instead of jumping.
                //
                //  The slider range is 5–60 seconds.  onMoved updates
                //  persist.slideshowInterval live so the Timer's
                //  interval binding picks it up at the next tick.
                //  sync() is deferred to onPressedChanged (release)
                //  to avoid hammering the disk while dragging.
                // ─────────────────────────────────────────────────
                Item {
                    id: ssIntervalSection
                    width:  contentColumn.width
                    // Animate height: 0 when hidden, full height when visible
                    height: root._backdropType === "slideshow" ? ssIntervalInner.implicitHeight + 8 : 0
                    clip:   true

                    Behavior on height { NumberAnimation { duration: 220; easing.type: Easing.InOutCubic } }

                    visible: height > 0

                    Column {
                        id:     ssIntervalInner
                        width:  parent.width
                        spacing: 0

                        SectionLabel { label: "SLIDESHOW INTERVAL" }

                        Item {
                            width:  parent.width
                            height: 68

                            Column {
                                anchors {
                                    left:           parent.left
                                    right:          parent.right
                                    leftMargin:     16
                                    rightMargin:    16
                                    verticalCenter: parent.verticalCenter
                                }
                                spacing: 6

                                // Label row: description + live value
                                Row {
                                    width: parent.width

                                    Text {
                                        width: parent.width - ssIntervalVal.implicitWidth
                                        text:  "Image Duration"
                                        color: Qt.rgba(1, 1, 1, 0.50)
                                        font { pixelSize: 11; family: "sans-serif" }
                                    }

                                    Text {
                                        id: ssIntervalVal
                                        text: root.settings !== null
                                              ? root.settings.slideshowInterval + "s" : "15s"
                                        color: root._accent
                                        font { pixelSize: 11; bold: true; family: "sans-serif" }
                                        Behavior on color { ColorAnimation { duration: 400 } }
                                    }
                                }

                                Slider {
                                    id:       ssIntervalSlider
                                    width:    parent.width
                                    from:     5
                                    to:       60
                                    stepSize: 1
                                    value:    root.settings !== null ? root.settings.slideshowInterval : 15

                                    // Live update every drag step —
                                    // the Timer's interval binding picks this up immediately
                                    onMoved: {
                                        if (root.settings !== null)
                                            root.settings.slideshowInterval = Math.round(value)
                                    }

                                    // Flush to disk on release only
                                    onPressedChanged: {
                                        if (!pressed && root.settings !== null)
                                            root.settings.sync()
                                    }

                                    background: Rectangle {
                                        x:      ssIntervalSlider.leftPadding
                                        y:      ssIntervalSlider.topPadding +
                                                ssIntervalSlider.availableHeight / 2 - height / 2
                                        width:  ssIntervalSlider.availableWidth
                                        height: 4; radius: 2
                                        color:  Qt.rgba(1, 1, 1, 0.13)

                                        Rectangle {
                                            width:  ssIntervalSlider.visualPosition * parent.width
                                            height: parent.height; radius: parent.radius
                                            color:  root._accent
                                            Behavior on color { ColorAnimation { duration: 400 } }
                                        }
                                    }

                                    handle: Rectangle {
                                        x: ssIntervalSlider.leftPadding +
                                           ssIntervalSlider.visualPosition *
                                           (ssIntervalSlider.availableWidth - width)
                                        y: ssIntervalSlider.topPadding +
                                           ssIntervalSlider.availableHeight / 2 - height / 2

                                        width:  18; height: 18; radius: 9
                                        color:        ssIntervalSlider.pressed
                                                      ? root._accent : Qt.rgba(1, 1, 1, 0.92)
                                        border.color: root._accent
                                        border.width: 2

                                        scale: ssIntervalSlider.pressed ? 1.18 : 1.0
                                        Behavior on scale        { NumberAnimation { duration: 100 } }
                                        Behavior on color        { ColorAnimation  { duration: 150 } }
                                        Behavior on border.color { ColorAnimation  { duration: 400 } }
                                    }
                                }
                            }
                        }

                        SectionDivider {}
                    }
                }

                // ─────────────────────────────────────────────────
                //  SECTION: MULTI-MONITOR
                // ─────────────────────────────────────────────────
                SectionLabel { label: "MULTI-MONITOR" }

                Item {
                    width:  parent.width
                    height: 58

                    Rectangle {
                        id: monitorContainer
                        anchors {
                            left:           parent.left
                            right:          parent.right
                            leftMargin:     16
                            rightMargin:    16
                            verticalCenter: parent.verticalCenter
                        }
                        height:       34
                        radius:       8
                        clip:         true
                        color:        Qt.rgba(1, 1, 1, 0.04)
                        border.color: Qt.rgba(1, 1, 1, 0.13)
                        border.width: 1

                        Row {
                            anchors.fill: parent

                            Repeater {
                                model: root._monitorModes

                                Rectangle {
                                    width:  monitorContainer.width / root._monitorModes.length
                                    height: monitorContainer.height

                                    readonly property bool _sel: {
                                        if (root.settings === null) return index === 0
                                        return root.settings.activeMultiMonitorMode === modelData.value
                                    }

                                    color: _sel
                                           ? Qt.rgba(root._accent.r, root._accent.g, root._accent.b, 0.28)
                                           : (segMa.containsMouse ? Qt.rgba(1, 1, 1, 0.09) : "transparent")
                                    Behavior on color { ColorAnimation { duration: 130 } }

                                    Rectangle {
                                        anchors { right: parent.right; top: parent.top; bottom: parent.bottom }
                                        width:   1
                                        visible: index < root._monitorModes.length - 1
                                        color:   Qt.rgba(1, 1, 1, 0.12)
                                    }

                                    Text {
                                        anchors.centerIn: parent
                                        text:  modelData.label
                                        color: parent._sel ? root._accent : Qt.rgba(1, 1, 1, 0.62)
                                        font { pixelSize: 11; bold: parent._sel; family: "sans-serif" }
                                        Behavior on color { ColorAnimation { duration: 130 } }
                                    }

                                    MouseArea {
                                        id:           segMa
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape:  Qt.PointingHandCursor
                                        onClicked: {
                                            if (root.settings === null) return
                                            root.settings.activeMultiMonitorMode = modelData.value
                                            root.settings.sync()
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                SectionDivider {}

                // ─────────────────────────────────────────────────
                //  SECTION: CLOCK FORMAT
                // ─────────────────────────────────────────────────
                SectionLabel { label: "CLOCK FORMAT" }

                Item {
                    width:  parent.width
                    height: 58

                    Rectangle {
                        id: clockTrack
                        anchors {
                            left:           parent.left
                            right:          parent.right
                            leftMargin:     16
                            rightMargin:    16
                            verticalCenter: parent.verticalCenter
                        }
                        height:       36
                        radius:       18
                        color:        Qt.rgba(1, 1, 1, 0.06)
                        border.color: Qt.rgba(1, 1, 1, 0.13)
                        border.width: 1

                        readonly property bool _is24h:
                            root.settings === null || root.settings.clockFormat !== "12h"

                        Rectangle {
                            id: clockThumb
                            width:  clockTrack.width / 2 - 4
                            height: clockTrack.height - 6
                            y:      3
                            x:      clockTrack._is24h ? 3 : clockTrack.width / 2 + 1
                            radius: height / 2
                            color:  Qt.rgba(root._accent.r, root._accent.g, root._accent.b, 0.82)

                            Behavior on x     { NumberAnimation { duration: 220; easing.type: Easing.InOutCubic } }
                            Behavior on color { ColorAnimation  { duration: 400 } }
                        }

                        Text {
                            width:               parent.width / 2
                            height:              parent.height
                            text:                "24h"
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment:   Text.AlignVCenter
                            color: clockTrack._is24h ? "white" : Qt.rgba(1, 1, 1, 0.40)
                            font { pixelSize: 13; bold: clockTrack._is24h; family: "sans-serif" }
                            Behavior on color { ColorAnimation { duration: 200 } }
                        }

                        Text {
                            x:                   parent.width / 2
                            width:               parent.width / 2
                            height:              parent.height
                            text:                "12h"
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment:   Text.AlignVCenter
                            color: !clockTrack._is24h ? "white" : Qt.rgba(1, 1, 1, 0.40)
                            font { pixelSize: 13; bold: !clockTrack._is24h; family: "sans-serif" }
                            Behavior on color { ColorAnimation { duration: 200 } }
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape:  Qt.PointingHandCursor
                            onClicked: {
                                if (root.settings === null) return
                                root.settings.clockFormat = clockTrack._is24h ? "12h" : "24h"
                                root.settings.sync()
                            }
                        }
                    }
                }

                SectionDivider {}

                // ─────────────────────────────────────────────────
                //  SECTION: CARD OPACITY
                // ─────────────────────────────────────────────────
                SectionLabel { label: "CARD OPACITY" }

                Item {
                    width:  parent.width
                    height: 68

                    Column {
                        anchors {
                            left:           parent.left
                            right:          parent.right
                            leftMargin:     16
                            rightMargin:    16
                            verticalCenter: parent.verticalCenter
                        }
                        spacing: 6

                        Row {
                            width: parent.width

                            Text {
                                width: parent.width - opacityPct.implicitWidth
                                text:  "Login Card Opacity"
                                color: Qt.rgba(1, 1, 1, 0.50)
                                font { pixelSize: 11; family: "sans-serif" }
                            }

                            Text {
                                id: opacityPct
                                text: root.settings !== null
                                      ? Math.round(root.settings.loginCardOpacity * 100) + "%" : "85%"
                                color: root._accent
                                font { pixelSize: 11; bold: true; family: "sans-serif" }
                                Behavior on color { ColorAnimation { duration: 400 } }
                            }
                        }

                        Slider {
                            id:       opacitySlider
                            width:    parent.width
                            from:     0.20
                            to:       1.00
                            stepSize: 0.01
                            value:    root.settings !== null ? root.settings.loginCardOpacity : 0.85

                            onMoved: {
                                if (root.settings !== null)
                                    root.settings.loginCardOpacity = value
                            }

                            onPressedChanged: {
                                if (!pressed && root.settings !== null)
                                    root.settings.sync()
                            }

                            background: Rectangle {
                                x:      opacitySlider.leftPadding
                                y:      opacitySlider.topPadding +
                                        opacitySlider.availableHeight / 2 - height / 2
                                width:  opacitySlider.availableWidth
                                height: 4; radius: 2
                                color:  Qt.rgba(1, 1, 1, 0.13)

                                Rectangle {
                                    width:  opacitySlider.visualPosition * parent.width
                                    height: parent.height; radius: parent.radius
                                    color:  root._accent
                                    Behavior on color { ColorAnimation { duration: 400 } }
                                }
                            }

                            handle: Rectangle {
                                x: opacitySlider.leftPadding +
                                   opacitySlider.visualPosition *
                                   (opacitySlider.availableWidth - width)
                                y: opacitySlider.topPadding +
                                   opacitySlider.availableHeight / 2 - height / 2

                                width:  18; height: 18; radius: 9
                                color:        opacitySlider.pressed
                                              ? root._accent : Qt.rgba(1, 1, 1, 0.92)
                                border.color: root._accent
                                border.width: 2

                                scale: opacitySlider.pressed ? 1.18 : 1.0
                                Behavior on scale        { NumberAnimation { duration: 100 } }
                                Behavior on color        { ColorAnimation  { duration: 150 } }
                                Behavior on border.color { ColorAnimation  { duration: 400 } }
                            }

                            activeFocusOnTab:  true
                            KeyNavigation.tab:     accentSection
                            KeyNavigation.backtab: accentSection
                        }
                    }
                }

                SectionDivider {}

                // ─────────────────────────────────────────────────
                //  SECTION: ACCENT COLOR
                // ─────────────────────────────────────────────────
                SectionLabel { label: "ACCENT COLOR" }

                Item {
                    id: accentSection
                    width:  parent.width
                    height: 88

                    activeFocusOnTab:  true
                    KeyNavigation.tab:     opacitySlider
                    KeyNavigation.backtab: opacitySlider

                    Row {
                        anchors {
                            left:           parent.left
                            right:          parent.right
                            leftMargin:     16
                            rightMargin:    16
                            verticalCenter: parent.verticalCenter
                        }

                        Repeater {
                            model: accentModel

                            Item {
                                width:  (accentSection.width - 32) / accentModel.count
                                height: 80

                                readonly property bool _sel:
                                    root.settings !== null &&
                                    root.settings.accentColor === model.hex

                                // Outer selection ring
                                Rectangle {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    anchors.top:              parent.top
                                    anchors.topMargin:        6
                                    width:  parent._sel ? 48 : 38
                                    height: width; radius: width / 2
                                    color:  "transparent"
                                    border.color: parent._sel ? model.hex : Qt.rgba(1, 1, 1, 0.0)
                                    border.width: 2
                                    opacity: 0.72

                                    Behavior on width        { NumberAnimation { duration: 180 } }
                                    Behavior on border.color { ColorAnimation  { duration: 200 } }
                                }

                                // Colour fill circle
                                Rectangle {
                                    id: swatchCircle
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    anchors.top:              parent.top
                                    anchors.topMargin:        12
                                    width:  parent._sel ? 36 : 28
                                    height: width; radius: width / 2
                                    color:  model.hex

                                    Behavior on width {
                                        NumberAnimation { duration: 180; easing.type: Easing.OutBack }
                                    }

                                    scale: swMa.containsMouse ? 1.12 : 1.0
                                    Behavior on scale {
                                        NumberAnimation { duration: 120; easing.type: Easing.OutBack }
                                    }

                                    Text {
                                        anchors.centerIn: parent
                                        visible:  parent.parent._sel
                                        text:     "✓"
                                        color:    Qt.rgba(0, 0, 0, 0.55)
                                        font { pixelSize: 13; bold: true; family: "sans-serif" }
                                    }
                                }

                                Text {
                                    anchors {
                                        top:              swatchCircle.bottom
                                        topMargin:        5
                                        horizontalCenter: parent.horizontalCenter
                                    }
                                    text:  model.label
                                    color: parent._sel ? model.hex : Qt.rgba(1, 1, 1, 0.32)
                                    font { pixelSize: 9; family: "sans-serif" }
                                    Behavior on color { ColorAnimation { duration: 200 } }
                                }

                                MouseArea {
                                    id:           swMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape:  Qt.PointingHandCursor
                                    onClicked: {
                                        if (root.settings === null) return
                                        root.settings.accentColor = model.hex
                                        root.settings.sync()
                                    }
                                }
                            }
                        }
                    }
                }

                // Bottom breathing room
                Item { width: parent.width; height: 28 }

            } // Column
        }     // ScrollView

    }         // FocusScope drawerScope


    // ─────────────────────────────────────────────────────────────
    //  INLINE COMPONENT DEFINITIONS
    // ─────────────────────────────────────────────────────────────

    // All-caps section heading with live accent colour
    component SectionLabel: Item {
        property string label: ""
        width:  contentColumn.width
        height: 34

        Text {
            anchors {
                left:           parent.left
                leftMargin:     16
                verticalCenter: parent.verticalCenter
            }
            text:  label
            color: Qt.rgba(root._accent.r, root._accent.g, root._accent.b, 0.82)
            font {
                pixelSize:     10
                bold:          true
                letterSpacing: 1.5
                family:        "sans-serif"
            }
            Behavior on color { ColorAnimation { duration: 400 } }
        }
    }

    // 1 px hairline rule between sections
    component SectionDivider: Rectangle {
        width:  contentColumn.width
        height: 1
        color:  Qt.rgba(1, 1, 1, 0.07)
    }

} // Item root
