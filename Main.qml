// ============================================================
//  Theme   : aurora-greeter
//  Author  : Biryukov Nikita (@execorn)
//  License : CC-BY-SA-4.0 / MIT
// ============================================================

import QtQuick 2.15
import QtQuick.Controls 2.15
import QtMultimedia 6.0
import SddmComponents 2.0
import Qt.labs.settings 1.0
import "components"

Item {
    id: root

    // Unique ID for this screen instance
    readonly property string screenId: "screen_" + (typeof primaryScreen !== "undefined" && primaryScreen ? "PRIMARY" : "AUX") + "_" + Math.random().toString(36).substr(2, 5) + "_" + Screen.width + "x" + Screen.height
    readonly property bool isPrimary: typeof primaryScreen !== "undefined" && primaryScreen

    // ── Per-monitor geometry ─────────────────────────────────────────────
    width:  Screen.width
    height: Screen.height

    // focus: true ensures this root Item always receives keyboard events.
    // SDDM greeter has no window manager, so Qt.ApplicationShortcut never
    // fires — we rely on Keys.onPressed on the permanently-focused root.
    focus: true

    LayoutMirroring.enabled:         Qt.locale().textDirection === Qt.RightToLeft
    LayoutMirroring.childrenInherit: true

    // ─────────────────────────────────────────────────────────────────────
    //  PERSISTENT SETTINGS — pure QML/JS, no QtCore.Settings required
    //
    //  Reads from / writes to an INI file at:
    //    /var/lib/sddm/.config/AuroraGreeter/settings.conf
    //
    //  The sddm system user must own that directory with write access.
    //  install.sh creates it with chown sddm:sddm + chmod 750.
    //
    //  Call persist.sync() after writing any property to flush to disk.
    // ─────────────────────────────────────────────────────────────────────
    QtObject {
        id: persist

        // Heuristic to detect system mode vs local dev
        readonly property bool _isSystemMode: Qt.resolvedUrl(".").toString().startsWith("file:///usr/share/sddm/themes/")

        // ── Config file location ──────────────────────────────────────
        property string _configPath: _isSystemMode
            ? "file:///var/lib/sddm/.config/AuroraGreeter/settings.conf"
            : Qt.resolvedUrl("settings.conf").toString()
        property string _configPathRaw: _configPath.replace(/^file:\/\//, "")

        // ── Live properties ───────────────────────────────────────────
        property string activePlaylist:         "playlists/Background.mp4"
        property string activeMultiMonitorMode: "primary-only"
        property string clockFormat:            "24h"
        property real   loginCardOpacity:       0.85
        property string accentColor:            "#89b4fa"

        // Backdrop type: "video" | "image" | "slideshow" | "color"
        property string activeBackgroundType:   "video"

        // Slideshow interval in seconds (5–60)
        property int    slideshowInterval:      15

        // Solid background colour used when activeBackgroundType === "color"
        property string backgroundColor:        "#1e1e2e"

        // [v4] Separate source for image / slideshow modes.
        //  NEVER set this to a video M3U — Image {} cannot render .mov.
        //  Defaults to the bundled fallback image which is always present.
        property string activeMediaSource:      "backgrounds/background.jpg"

        // [v4] Performance profile: "auto" | "high" | "low"
        //   auto — screen-adaptive resolution cap (≤1920 px wide → 2K URLs)
        //   high — always use source URLs unchanged; full animation durations
        //   low  — force 2K, reduced animation durations (less GPU compositing)
        property string performanceMode:        "auto"

        // [v5] Day/night scheduling toggle: true = time-based, false = manual/hardcoded
        property bool   useDayNightSchedule:    true

        // Indicator if the configuration file was loaded and parsed successfully from disk
        property bool _loaded: false

        // Simple INI file parser
        function _parseIni(text) {
            var lines = text.split("\n");
            var data = {};
            for (var i = 0; i < lines.length; i++) {
                var line = lines[i].trim();
                if (line.startsWith("[") || line === "" || line.startsWith("#") || line.startsWith(";")) {
                    continue;
                }
                var parts = line.split("=");
                if (parts.length >= 2) {
                    var key = parts[0].trim();
                    var val = parts.slice(1).join("=").trim();
                    if (val === "true") val = true;
                    else if (val === "false") val = false;
                    else if (!isNaN(val) && val !== "") {
                        if (val.indexOf(".") !== -1) val = parseFloat(val);
                        else val = parseInt(val, 10);
                    }
                    data[key] = val;
                }
            }
            return data;
        }

        // ── load(): read INI from disk, overwrite properties ──────────
        //  Called once from Component.onCompleted.
        function load() {
            var xhr = new XMLHttpRequest()
            xhr.open("GET", _configPath, false)
            try {
                xhr.send()
            } catch(e) {
                // Try local fallback (dev/test-mode)
                _configPath = _isSystemMode
                    ? "file:///var/lib/sddm/.config/AuroraGreeter/settings.conf"
                    : Qt.resolvedUrl("settings.conf").toString()
                xhr.open("GET", _configPath, false)
                try {
                    xhr.send()
                } catch(e2) {
                    return
                }
            }
            if (xhr.status !== 0 && xhr.status !== 200) return
            if (!xhr.responseText || xhr.responseText.trim() === "") return
            try {
                var data = _parseIni(xhr.responseText)
                if (typeof data.activePlaylist         === "string") activePlaylist         = data.activePlaylist
                if (typeof data.activeMultiMonitorMode === "string") activeMultiMonitorMode = data.activeMultiMonitorMode
                if (typeof data.clockFormat            === "string") clockFormat            = data.clockFormat
                if (typeof data.loginCardOpacity       === "number") loginCardOpacity       = data.loginCardOpacity
                if (typeof data.accentColor            === "string") accentColor            = data.accentColor
                if (typeof data.activeBackgroundType   === "string") activeBackgroundType   = data.activeBackgroundType
                if (typeof data.slideshowInterval      === "number") slideshowInterval      = data.slideshowInterval
                if (typeof data.backgroundColor        === "string") backgroundColor        = data.backgroundColor
                if (typeof data.activeMediaSource      === "string") activeMediaSource      = data.activeMediaSource
                if (typeof data.performanceMode        === "string") performanceMode        = data.performanceMode

                var hasCustomPlaylist = (typeof data.activePlaylist === "string" && data.activePlaylist !== "playlists/Background.mp4")
                if (typeof data.useDayNightSchedule   === "boolean") {
                    useDayNightSchedule = data.useDayNightSchedule
                } else {
                    useDayNightSchedule = !hasCustomPlaylist
                }

                _loaded = true
            } catch(e) {
                console.warn("[AuroraGreeter] Settings INI parse error:", e)
            }
        }

        // ── sync(): write current property values back to disk ────────
        //  Called by ConfigDrawer whenever the user changes a setting.
        function sync() {
            settingsStore.activePlaylist = activePlaylist
            settingsStore.activeMultiMonitorMode = activeMultiMonitorMode
            settingsStore.clockFormat = clockFormat
            settingsStore.loginCardOpacity = loginCardOpacity
            settingsStore.accentColor = accentColor
            settingsStore.activeBackgroundType = activeBackgroundType
            settingsStore.slideshowInterval = slideshowInterval
            settingsStore.backgroundColor = backgroundColor
            settingsStore.activeMediaSource = activeMediaSource
            settingsStore.performanceMode = performanceMode
            settingsStore.useDayNightSchedule = useDayNightSchedule
            settingsStore.sync()
        }
    }

    Settings {
        id: settingsStore
        fileName: persist._configPathRaw
        property string activePlaylist
        property string activeMultiMonitorMode
        property string clockFormat
        property real   loginCardOpacity
        property string accentColor
        property string activeBackgroundType
        property int    slideshowInterval
        property string backgroundColor
        property string activeMediaSource
        property string performanceMode
        property bool   useDayNightSchedule
    }

    // ─────────────────────────────────────────────────────────────────────
    //  ROOT-LEVEL BRIDGING PROPERTIES
    //
    //  Single source of truth for every child component and the
    //  ConfigDrawer.  Writing to persist.* propagates here via
    //  the property binding engine; children that read root.* update
    //  automatically.
    // ─────────────────────────────────────────────────────────────────────
    property string activePlaylist:         persist.activePlaylist
    property string activeMultiMonitorMode: persist.activeMultiMonitorMode
    property string clockFormat:            persist.clockFormat
    property real   loginCardOpacity:       persist.loginCardOpacity
    property string accentColor:            persist.accentColor

    // Backdrop engine bridging
    property string activeBackgroundType:   persist.activeBackgroundType
    property int    slideshowInterval:      persist.slideshowInterval
    property string backgroundColor:        persist.backgroundColor

    // [v4] Separate image/slideshow source (never a video M3U)
    property string activeMediaSource:      persist.activeMediaSource

    // [v4] Performance profile bridging
    property string performanceMode:        persist.performanceMode

    // [v5] Day/night scheduling toggle bridging
    property bool   useDayNightSchedule:    persist.useDayNightSchedule

    // ─────────────────────────────────────────────────────────────────────
    //  PERFORMANCE PROFILE — COMPUTED ANIMATION DURATIONS              [v4]
    //
    //  All Behavior blocks read from these computed properties so that
    //  switching the performance profile in ConfigDrawer hot-updates
    //  every animation in the theme simultaneously.
    //
    //  "low"  → shorter durations (less GPU compositing per frame)
    //  "high" → cinematic durations (best visual quality)
    //  "auto" → same as "high" (auto only affects resolution, not animation)
    //
    //  Duration map:
    //    _animDuration     — primary opacity crossfade (image/slideshow/video)
    //    _fastAnimDuration — UI elements, colour swaps, dim overlay
    //    _colorAnimDuration— ColorAnimation blocks (accent, background color)
    //    _swapDelay        — _swapSlideshowLayers timer: must be > _animDuration
    // ─────────────────────────────────────────────────────────────────────

    // Whether the effective (resolved) mode is "low".
    // "auto" resolves to "low" when this screen is ≤ 1920 px wide.
    // "low" is always low. "high" is always high.
    readonly property bool _isLowPerf: {
        if (root.performanceMode === "low") return true
        if (root.performanceMode === "auto") return Screen.width <= 1920
        return false   // "high"
    }

    // Primary crossfade duration: video reveal, image fade, slideshow dissolve
    readonly property int _animDuration:     _isLowPerf ? 300 : 800

    // Secondary animation duration: dim overlay, UI opacity
    readonly property int _fastAnimDuration: _isLowPerf ? 150 : 500

    // Colour transition duration: accent changes, background color swaps
    readonly property int _colorAnimDuration: _isLowPerf ? 150 : 400

    // Video surface reveal (intentionally slower for cinematic feel in high)
    readonly property int _videoFadeDuration: _isLowPerf ? 400 : 1200

    // Background color swap (solidBlack.color in color mode)
    readonly property int _bgColorDuration: _isLowPerf ? 200 : 600

    // _swapSlideshowLayers fires after the crossfade finishes.
    // Must be slightly longer than _animDuration so the swap is invisible.
    readonly property int _swapDelay: _animDuration + 20

    // ─────────────────────────────────────────────────────────────────────
    //  MULTI-MONITOR MODE
    //
    //  Priority: persist.activeMultiMonitorMode → config.multiMonitorMode
    //            → "mirror" (hard default)
    //
    //  Accepted values:
    //    "mirror"          – video + UI on every connected screen
    //    "primary-only"    – video on all screens; UI on primary only
    //    "blank-auxiliary" – primary gets video + UI;
    //                        auxiliary screens render solid black
    // ─────────────────────────────────────────────────────────────────────
    readonly property string monitorMode: {
        var saved = root.activeMultiMonitorMode
        if (saved !== "" && saved !== undefined) return saved
        var cfgVal = (typeof config.multiMonitorMode !== "undefined")
                     ? config.multiMonitorMode : ""
        if (cfgVal !== "") return cfgVal
        return "mirror"
    }

    // Whether THIS screen instance should render the video background
    readonly property bool showBackground: (monitorMode !== "blank-auxiliary") || primaryScreen

    // Whether THIS screen instance should render the login UI
    readonly property bool showUI: (monitorMode === "mirror") || primaryScreen

    // ─────────────────────────────────────────────────────────────────────
    //  BACKDROP MODE SHORTCUTS  (read by the layer stack below)
    // ─────────────────────────────────────────────────────────────────────
    readonly property bool _modeVideo:     root.activeBackgroundType === "video"
    readonly property bool _modeImage:     root.activeBackgroundType === "image"
    readonly property bool _modeSlideshow: root.activeBackgroundType === "slideshow"
    readonly property bool _modeColor:     root.activeBackgroundType === "color"

    // ─────────────────────────────────────────────────────────────────────
    //  CROSS-BOUNDARY STATE
    // ─────────────────────────────────────────────────────────────────────
    property string loginErrorText:  ""
    property color  loginErrorColor: "white"

    property bool uiVisible: false

    // Playlist runtime state (video mode + slideshow mode share the parsed list)
    property var playlistEntries: []
    property int playlistIndex:   0

    // ─────────────────────────────────────────────────────────────────────
    //  SLIDESHOW INTERNAL STATE
    //
    //  _ssEntries — parsed image paths for the slideshow playlist.
    //  _ssIndex   — index of the currently visible image.
    //  _ssFront   — which image element is currently "front" (visible).
    //               true  → fallbackImage is front, slideshowBufferImage is back.
    //               false → slideshowBufferImage is front, fallbackImage is back.
    //
    //  The crossfade works by:
    //    1. Loading next image into the hidden (back) element.
    //    2. Waiting for Image.Ready on the back element.
    //    3. Animating front opacity to 0 (reveals the back).
    //    4. _swapSlideshowLayers fires after _swapDelay ms and swaps
    //       source/roles so the elements cycle without a visible flash.
    // ─────────────────────────────────────────────────────────────────────
    property var  _ssEntries: []
    property int  _ssIndex:   0
    property bool _ssFront:   true   // true = fallbackImage is the visible front

    // Guard flag: true while _reloadPlaylist() is in progress.
    // Suppresses the NoMedia status signal's _activateImageFallback() call
    // that fires between backgroundVideo.stop() and the new source being set.
    // Cleared in onMediaStatusChanged when BufferedMedia fires (or on error).
    property bool _videoReloading: false


    // ─────────────────────────────────────────────────────────────────────
    //  SDDM BINDINGS
    // ─────────────────────────────────────────────────────────────────────
    TextConstants { id: textConstants }

    // In Qt6, FontLoader.name is a READ-ONLY output property (the detected
    // family after loading a font file).  config.displayFont is already a
    // font-family name string, so no loading is needed — expose it directly
    // via a plain QtObject so that all existing displayFont.name references
    // in child items continue to work without modification.
    QtObject {
        id: displayFont
        readonly property string name: (typeof config !== "undefined" &&
                                        typeof config.displayFont !== "undefined" &&
                                        config.displayFont !== "")
                                       ? config.displayFont
                                       : "sans-serif"
    }

    Connections {
        target: sddm

        function onLoginSucceeded() {
            // The compositor will destroy the greeter — no action needed.
        }

        function onLoginFailed() {
            root.loginErrorColor = "#dc322f"
            root.loginErrorText  = textConstants.loginFailed
        }
    }

    // ─────────────────────────────────────────────────────────────────────
    //  BACKGROUND LAYER STACK   (z-order 0 → 3, back to front)
    //
    //  Layer assignments:
    //    z 0  solidBlack          — always present; colour canvas / "color" mode
    //    z 1  slideshowBufferImg  — slideshow back buffer (hidden when not in use)
    //    z 2  fallbackImage       — static image / slideshow front; video fallback
    //    z 3  videoSurface        — video output (invisible outside "video" mode)
    //
    //  Only the active mode's layer(s) are visible.  All other layers have
    //  opacity 0 and visible: false so the GPU skips rasterising them.
    // ─────────────────────────────────────────────────────────────────────

    // ── Layer 0: Solid canvas — also the "color" mode backdrop ───────────
    //
    //  In "color" mode this is the only visible layer.  Its color property
    //  is bound to persist.backgroundColor so it hot-updates from the drawer.
    //  In all other modes it remains black and is covered by higher layers.
    Rectangle {
        id: solidBlack
        anchors.fill: parent
        z: 0

        // Bind to the persisted backgroundColor in color-mode;
        // fall back to black in all other modes.
        color: root._modeColor ? root.backgroundColor : "black"

        // Smooth transition when the user changes color-mode background.
        // Duration is profile-aware: shorter in "low" mode.
        Behavior on color {
            ColorAnimation { duration: root._bgColorDuration; easing.type: Easing.InOutQuad }
        }
    }

    // ── Layer 1: Slideshow back-buffer image ──────────────────────────────
    //
    //  This layer is only active during "slideshow" mode.  It sits behind
    //  fallbackImage (the front) and receives the next image while the
    //  current one is still visible.  The crossfade is achieved by fading
    //  fallbackImage's opacity to 0, revealing this element, then swapping
    //  sources so the two layers swap roles without a visible stutter.
    Image {
        id: slideshowBufferImage
        anchors.fill: parent
        fillMode:     Image.PreserveAspectCrop
        asynchronous: true
        cache:        false
        z: 1

        // Only rendered during slideshow mode and only on screens that
        // should show a background at all.
        visible:  root.showBackground && root._modeSlideshow
        opacity:  0   // always starts hidden; crossfade logic drives opacity

        // No Behavior here: this layer must snap to full opacity instantly
        // after the crossfade swap so the front layer can re-hide behind it.
    }

    // ── Layer 2: Static image / slideshow front / video fallback ─────────
    //
    //  Multi-purpose image layer:
    //    "image"     → rendered at full opacity, fills screen.
    //    "slideshow" → the currently visible slide (front buffer).
    //    "video"     → emergency fallback if MediaPlayer fails.
    //    "color"     → opacity 0 (not shown).
    Image {
        id: fallbackImage
        anchors.fill: parent
        fillMode:     Image.PreserveAspectCrop
        asynchronous: true
        cache:        false
        z: 2

        // Visible in image/slideshow mode and as the video fallback.
        // Invisible in color mode (solidBlack handles the backdrop).
        visible: root.showBackground && !root._modeColor
        opacity: 0

        // Duration bound to performance profile.
        Behavior on opacity {
            NumberAnimation { duration: root._animDuration; easing.type: Easing.InOutQuad }
        }

        onStatusChanged: {
            if (status === Image.Error) {
                console.warn("[AuroraGreeter] Image load failed:", source,
                             "\u2014 solid black background will be used.")
            }
            // Reveal in image mode
            if (status === Image.Ready && root._modeImage) {
                opacity = 1.0
            }
            // Reveal as slideshow front buffer (when _ssFront === true)
            // This fires when _initSlideshow() loads the first image.
            if (status === Image.Ready && root._modeSlideshow && root._ssFront) {
                opacity = 1.0
            }
        }
    }

    // ─────────────────────────────────────────────────────────────────────
    //  SINGLE-PIPELINE VIDEO ENGINE
    //
    //  Only active when activeBackgroundType === "video".
    //  In all other modes the player is stopped and stays at source: ""
    //  so no decode threads, no VRAM upload, no GPU load.
    // ─────────────────────────────────────────────────────────────────────
    MediaPlayer {
        id: backgroundVideo

        loops: MediaPlayer.Infinite

        // NOTE: No audioOutput attached — intentionally omitted.
        // SDDM's greeter runs under a restricted user with no audio
        // device access.  Even a muted AudioOutput { volume: 0 } forces
        // Qt6 Multimedia / GStreamer to negotiate a PipeWire/ALSA
        // pipeline, which triggers a fatal SIGSEGV (spaVisitChoice
        // null-pointer dereference) inside the sandboxed session.
        // Omitting the property entirely prevents Qt from allocating
        // any audio pipeline.

        videoOutput: videoSurface

        onMediaStatusChanged: {
            console.log("[Aurora] MediaPlayer status:", mediaStatus,
                        "| src:", source.toString().split("/").pop(),
                        "| playbackState:", playbackState,
                        "| reloading:", root._videoReloading)

            // Guard: ignore status changes when not in video mode
            if (!root._modeVideo) return

            switch (mediaStatus) {
                case MediaPlayer.LoadingMedia:
                    // Normal; pipeline is buffering the new source.
                    break

                case MediaPlayer.BufferedMedia:
                    // New track fully buffered — animate the surface back in.
                    console.log("[Aurora] Video buffered — revealing surface")
                    root._videoReloading = false
                    videoSurface.opacity = 1.0
                    break

                case MediaPlayer.NoMedia:
                    // Fires during hot-reload between stop() and new source being set.
                    // _videoReloading suppresses false _activateImageFallback() calls.
                    if (root._videoReloading) {
                        console.log("[Aurora] NoMedia during reload — suppressing fallback")
                        break
                    }
                    console.warn("[Aurora] Video: NoMedia — no source set.")
                    _activateImageFallback()
                    break

                case MediaPlayer.InvalidMedia:
                    // ALWAYS clear the reload guard so the next attempt can proceed.
                    // Also reset source to "" to put the Qt6 pipeline back into
                    // a clean NoMedia state — without this the player ignores
                    // subsequent play() calls after a failed source.
                    console.warn("[Aurora] Video source invalid or missing:", source)
                    root._videoReloading = false
                    backgroundVideo.source = ""
                    _activateImageFallback()
                    break

                default:
                    break
            }
        }

        onErrorOccurred: function(error, errorString) {
            if (!root._modeVideo) return
            console.warn("[Aurora] MediaPlayer error (code", error, "):", errorString)
            // Clear the reload guard and reset player state (same reason as InvalidMedia).
            root._videoReloading = false
            Qt.callLater(function() { backgroundVideo.source = "" })
            _activateImageFallback()
        }

        onPlaybackStateChanged: {
            console.log("[Aurora] MediaPlayer playbackState →", playbackState,
                        "| src:", source.toString().split("/").pop())
        }

    }

    // ── Layer 3: Video surface ────────────────────────────────────────────
    //
    //  Only visible in video mode.  Opacity is animated:
    //    • fades to 0 when a track swap begins (_reloadPlaylist)
    //    • fades back to 1.0 once MediaPlayer.BufferedMedia fires
    VideoOutput {
        id: videoSurface
        anchors.fill: parent
        fillMode: VideoOutput.PreserveAspectCrop
        z: 3

        // Visible only in video mode and only on screens that show backgrounds.
        visible:  root.showBackground && root._modeVideo
        opacity:  0

        // Duration bound to performance profile.
        // Intentionally slower than _animDuration for a cinematic reveal in
        // "high" mode; still visible (400 ms) in "low" mode.
        Behavior on opacity {
            NumberAnimation { duration: root._videoFadeDuration; easing.type: Easing.InOutQuad }
        }
    }

    // ─────────────────────────────────────────────────────────────────────
    //  SLIDESHOW TIMER
    //
    //  Fires every slideshowInterval seconds.  On each tick it:
    //    1. Picks the next image path from _ssEntries.
    //    2. Loads it into the back-buffer image element.
    //    3. The back-buffer's onStatusChanged starts the crossfade
    //       once the image is decoded and ready.
    //
    //  The timer is only running when activeBackgroundType === "slideshow"
    //  and _ssEntries has at least two entries.
    // ─────────────────────────────────────────────────────────────────────
    Timer {
        id: slideshowTimer

        // Interval is bound live to the persisted setting so changing the
        // slider in ConfigDrawer takes effect at the next tick.
        interval: root.slideshowInterval * 1000

        repeat:  true
        running: false   // started/stopped by _initSlideshow / mode guards

        onTriggered: {
            if (!root._modeSlideshow || root._ssEntries.length === 0) {
                stop()
                return
            }
            _advanceSlideshow()
        }
    }

    // ─────────────────────────────────────────────────────────────────────
    //  SLIDESHOW BACK-BUFFER READY HANDLER
    //
    //  When slideshowBufferImage finishes loading its next source we start
    //  the opacity crossfade.  Using a Connections block rather than an
    //  inline onStatusChanged on the element itself keeps the crossfade
    //  logic in one place alongside the Timer code.
    // ─────────────────────────────────────────────────────────────────────
    Connections {
        target: slideshowBufferImage

        function onStatusChanged() {
            if (!root._modeSlideshow) return
            if (slideshowBufferImage.status !== Image.Ready) return

            // The next image is decoded. Perform the crossfade.
            if (root._ssFront) {
                // fallbackImage is the front → fade it out to reveal the buffer
                fallbackImage.opacity = 0
                // After the opacity animation completes, swap roles.
                // _swapSlideshowLayers.interval is bound to root._swapDelay.
                _swapSlideshowLayers.start()
            } else {
                // slideshowBufferImage is the front → fade it out.
                // Reveal fallbackImage by fading out slideshowBufferImage.
                slideshowBufferImage.opacity = 0
                _swapSlideshowLayers.start()
            }
        }
    }

    // Short timer that fires after the crossfade opacity animation ends.
    // Its interval is bound to root._swapDelay (= _animDuration + 20) so it
    // always trails the fallbackImage Behavior regardless of performance profile.
    Timer {
        id: _swapSlideshowLayers

        // Bound to the computed swap delay so profile changes update it live.
        interval: root._swapDelay

        repeat:  false
        running: false

        onTriggered: {
            if (!root._modeSlideshow) return

            if (root._ssFront) {
                // Swap: make the buffer the new front.
                //  1. Bring buffer to full opacity instantly (no Behavior on it).
                slideshowBufferImage.opacity = 1.0
                //  2. fallbackImage is now fully hidden — sync its source to
                //     the same image so it becomes the idle back-buffer.
                fallbackImage.source  = slideshowBufferImage.source
                fallbackImage.opacity = 0   // keep hidden; next cycle it's the buffer
                root._ssFront = false
            } else {
                // Swap: make fallbackImage the new front again.
                //  1. fallbackImage already has the new image loaded (back-buffer role)
                //     and is at opacity 0 — reveal it.
                fallbackImage.opacity = 1.0
                //  2. Buffer is now hidden — sync its source so next cycle is ready.
                slideshowBufferImage.source  = fallbackImage.source
                slideshowBufferImage.opacity = 0
                root._ssFront = true
            }
        }
    }

    // ─────────────────────────────────────────────────────────────────────
    //  INTERACTION CAPTURE LAYER   (z 4)
    // ─────────────────────────────────────────────────────────────────────
    MouseArea {
        id: globalMouseArea
        anchors.fill: parent
        z: 4
        propagateComposedEvents: true

        onPressed: function(mouse) {
            _revealUI()
            if (config.autofocusInput === "true") {
                _focusAppropriateInput()
            }
            mouse.accepted = false
        }
    }

    // ─────────────────────────────────────────────────────────────────────
    //  GLOBAL KEYBOARD SHORTCUT  (Alt+S / Super+S — toggle Config Drawer)
    //
    //  WHY Keys.onPressed instead of Shortcut {}:
    //  Qt's Shortcut { context: Qt.ApplicationShortcut } requires the platform
    //  window manager to deliver a "window activated" event.  SDDM runs its
    //  greeter WITHOUT a traditional window manager (it is the only client on
    //  the X11 display / Wayland compositor).  As a result Qt never marks the
    //  greeter window as "active" in the WM sense, so ApplicationShortcut
    //  silently absorbs the key event (preventing the 's' from typing) but
    //  never fires onActivated.
    //
    //  The correct pattern for SDDM themes is to hold permanent focus on the
    //  root Item with focus:true (not just on primaryScreen) and intercept
    //  Alt+S in Keys.onPressed.  We set event.accepted = true for the
    //  shortcut so it doesn't fall through to any focused child, and leave it
    //  false for all other keys so normal typing is unaffected.
    // ─────────────────────────────────────────────────────────────────────
    Keys.onPressed: function(event) {
        var isAlt   = (event.modifiers & Qt.AltModifier)  !== 0
        var isMeta  = (event.modifiers & Qt.MetaModifier) !== 0
        var isS     = (event.key === Qt.Key_S)

        if ((isAlt || isMeta) && isS) {
            configDrawer.toggle()
            event.accepted = true   // consume — do NOT forward to text inputs
            return
        }

        // All other keys: reveal the login UI (e.g. user starts typing).
        // Do NOT accept — let the key propagate to the focused child input.
        _revealUI()
    }

    // ─────────────────────────────────────────────────────────────────────
    //  DIM OVERLAY   (z 5)
    // ─────────────────────────────────────────────────────────────────────
    Rectangle {
        id: dimOverlay
        anchors.fill: parent
        color:   Qt.rgba(0, 0, 0, 0.50)
        opacity: root.uiVisible ? 1.0 : 0.0
        // Hide entirely in "blank-auxiliary" mode on non-primary screens
        visible: root.showBackground || root._modeColor
        z: 5

        // Duration bound to performance profile.
        Behavior on opacity {
            NumberAnimation { duration: root._fastAnimDuration; easing.type: Easing.InOutQuad }
        }
    }

    // ─────────────────────────────────────────────────────────────────────
    //  UI LOADER   (z 6)
    // ─────────────────────────────────────────────────────────────────────
    Loader {
        id: uiLoader
        anchors.fill: parent
        z: 6
        active:          root.showUI
        sourceComponent: loginUIComponent
    }

    // ─────────────────────────────────────────────────────────────────────
    //  LOGIN UI COMPONENT
    // ─────────────────────────────────────────────────────────────────────
    Component {
        id: loginUIComponent

        Item {
            id: loginUI
            anchors.fill: parent

            // Duration bound to performance profile.
            opacity: root.uiVisible ? 1.0 : 0.0
            Behavior on opacity {
                NumberAnimation { duration: root._fastAnimDuration; easing.type: Easing.InOutQuad }
            }

            readonly property bool showLoginBtn: config.showLoginButton !== "false"

            function focusAppropriateInput() {
                if (usernameInput.text === "")
                    usernameInput.forceActiveFocus()
                else
                    passwordInput.forceActiveFocus()
            }

            // ── Clock ─────────────────────────────────────────────────────
            Clock {
                id: clock
                x: parent.width  * config.relativePositionX - clock.width  / 2
                y: parent.height * config.relativePositionY - clock.height / 2
                color: "white"
                timeFont.family: displayFont.name
                dateFont.family: displayFont.name
                clockFormat:     root.clockFormat
            }

            // ── Login Container ───────────────────────────────────────────
            Item {
                id: loginContainer

                // Centre the login block on the same horizontal axis as the
                // clock regardless of how wide the clock is.  Previously
                // anchors.left: clock.left caused right-shift on wide clocks.
                anchors.horizontalCenter: clock.horizontalCenter
                y: clock.y + clock.height + 30
                width:  Math.max(clock.implicitWidth, 360)
                height: loginColumn.implicitHeight

                Column {
                    id: loginColumn
                    anchors.left:  parent.left
                    anchors.right: parent.right
                    spacing: 10

                    // ── Username Row ──────────────────────────────────────
                    Item {
                        id: usernameRow
                        width:  parent.width
                        height: 40

                        Text {
                            id: usernameLabel
                            anchors {
                                left:           parent.left
                                verticalCenter: parent.verticalCenter
                            }
                            width: 90
                            text:   "Username"
                            horizontalAlignment: Text.AlignLeft
                            font.family:    displayFont.name
                            font.bold:      true
                            font.pixelSize: 14
                            color: "white"
                            elide: Text.ElideRight
                        }

                        TextBox {
                            id: usernameInput
                            anchors {
                                left:           usernameLabel.right
                                leftMargin:     config.usernameLeftMargin
                                right:          parent.right
                                verticalCenter: parent.verticalCenter
                            }
                            height:      parent.height
                            text:        userModel.lastUser
                            focus:       primaryScreen
                            font:        displayFont.name
                            color:       "#25000000"
                            borderColor: "transparent"
                            textColor:   "white"
                            accentColor: root.accentColor

                            Keys.onPressed: function(event) {
                                if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                                    sddm.login(usernameInput.text,
                                               passwordInput.text,
                                               sessionCombo.index)
                                    event.accepted = true
                                }
                            }

                            KeyNavigation.backtab: passwordInput
                            KeyNavigation.tab:     passwordInput
                        }
                    }

                    // ── Password Row ──────────────────────────────────────
                    Item {
                        id: passwordRow
                        width:  parent.width
                        height: 40

                        Text {
                            id: passwordLabel
                            anchors {
                                left:           parent.left
                                verticalCenter: parent.verticalCenter
                            }
                            width: 90
                            text:   textConstants.password
                            horizontalAlignment: Text.AlignLeft
                            font.family:    displayFont.name
                            font.bold:      true
                            font.pixelSize: 14
                            color: "white"
                            elide: Text.ElideRight
                        }

                        PasswordBox {
                            id: passwordInput
                            anchors {
                                left:           passwordLabel.right
                                leftMargin:     config.passwordLeftMargin
                                right:          parent.right
                                rightMargin:    loginUI.showLoginBtn ? 44 : 0
                                verticalCenter: parent.verticalCenter
                            }
                            height:      parent.height
                            font:        displayFont.name
                            color:       "#25000000"
                            borderColor: "transparent"
                            textColor:   "white"
                            tooltipBG:   "#25000000"
                            tooltipFG:   "#dc322f"
                            image:       Qt.resolvedUrl("components/resources/warning_red.png")
                            accentColor: root.accentColor
                            errorText:   root.loginErrorText

                            onTextChanged: {
                                clearPasswdButton.visible =
                                    (passwordInput.text !== "" &&
                                     config.showClearPasswordButton !== "false")
                            }

                            Keys.onPressed: function(event) {
                                if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                                    sddm.login(usernameInput.text,
                                               passwordInput.text,
                                               sessionCombo.index)
                                    event.accepted = true
                                }
                            }

                            KeyNavigation.backtab: usernameInput
                            KeyNavigation.tab:     loginButton
                        }

                        // Clear password button (×)
                        Button {
                            id: clearPasswdButton
                            visible: false
                            anchors {
                                right:          loginUI.showLoginBtn ? loginButton.left : parent.right
                                rightMargin:    4
                                verticalCenter: parent.verticalCenter
                            }
                            height: parent.height
                            width:  parent.height
                            text:          "x"
                            font:          displayFont.name
                            color:         "transparent"
                            border.color:  "transparent"
                            border.width:  0
                            disabledColor: "#dc322f"
                            activeColor:   "#393939"
                            pressedColor:  "#2aa198"

                            onClicked: {
                                passwordInput.text = ""
                                passwordInput.forceActiveFocus()
                            }
                        }

                        // Login button (>)
                        Button {
                            id: loginButton
                            visible: loginUI.showLoginBtn
                            anchors {
                                right:          parent.right
                                verticalCenter: parent.verticalCenter
                            }
                            height: parent.height
                            width:  44
                            text:          ">"
                            font:          displayFont.name
                            color:         "#393939"
                            border.color:  "#00000000"
                            disabledColor: "#dc322f"
                            activeColor:   "#268bd2"
                            pressedColor:  "#2aa198"
                            textColor:     "white"

                            onClicked: sddm.login(usernameInput.text,
                                                  passwordInput.text,
                                                  sessionCombo.index)

                            KeyNavigation.backtab: passwordInput
                            KeyNavigation.tab:     rebootButton
                        }
                    }

                    // ── Error message ─────────────────────────────────────
                    Text {
                        id: errorMessage
                        width:  parent.width
                        text:   root.loginErrorText
                        color:  root.loginErrorColor
                        font.family:    displayFont.name
                        font.pixelSize: 12
                        visible: root.loginErrorText !== ""
                        wrapMode: Text.WordWrap
                    }
                }
            }

            Rectangle {
                id: actionBar
                anchors {
                    top:              parent.top
                    horizontalCenter: parent.horizontalCenter
                }
                width:   parent.width
                height:  parent.height * 0.04
                color:   "transparent"
                visible: config.showTopBar !== "false"

                // Left group: session selector + keyboard layout picker
                Row {
                    id: leftRow
                    anchors {
                        left:    parent.left
                        margins: 5
                    }
                    height:  parent.height
                    spacing: 10

                    ComboBox {
                        id: sessionCombo
                        width:  145
                        height: 20
                        anchors.verticalCenter: parent.verticalCenter
                        color:       "transparent"
                        arrowColor:  "transparent"
                        textColor:   "#505050"
                        borderColor: "transparent"
                        hoverColor:  "#5692c4"
                        model: sessionModel
                        index: sessionModel.lastIndex

                        KeyNavigation.backtab: shutdownButton
                        KeyNavigation.tab:     passwordInput
                    }

                    ComboBox {
                        id: languageCombo
                        model:  keyboard.layouts
                        index:  keyboard.currentLayout
                        width:  50
                        height: 20
                        anchors.verticalCenter: parent.verticalCenter
                        color:       "transparent"
                        arrowColor:  "transparent"
                        textColor:   "white"
                        borderColor: "transparent"
                        hoverColor:  "#5692c4"

                        onValueChanged: keyboard.currentLayout = languageCombo.index

                        Connections {
                            target: keyboard
                            function onCurrentLayoutChanged() {
                                languageCombo.index = keyboard.currentLayout
                            }
                        }

                        rowDelegate: Rectangle {
                            color: "transparent"
                            Text {
                                anchors {
                                    margins: 4
                                    top:     parent.top
                                    bottom:  parent.bottom
                                }
                                verticalAlignment: Text.AlignVCenter
                                text:           modelItem ? modelItem.modelData.shortName : "??"
                                font.family:    displayFont.name
                                font.pixelSize: 14
                                color:          "#505050"
                            }
                        }

                        KeyNavigation.backtab: sessionCombo
                        KeyNavigation.tab:     usernameInput
                    }
                }

                // Right group: gear + reboot + shutdown
                Row {
                    id: rightRow
                    anchors {
                        right:   parent.right
                        margins: 5
                    }
                    height:  parent.height
                    spacing: 10

                    // ── Gear icon — opens ConfigDrawer ────────────────────
                    Rectangle {
                        id: gearButton
                        width:   parent.height
                        height:  parent.height
                        radius:  height / 2
                        color:   gearArea.containsMouse
                                 ? Qt.rgba(1, 1, 1, 0.15)
                                 : "transparent"
                        anchors.verticalCenter: parent.verticalCenter

                        Behavior on color { ColorAnimation { duration: 130 } }

                        rotation: gearArea.containsMouse ? 30 : 0
                        Behavior on rotation {
                            NumberAnimation { duration: 300; easing.type: Easing.OutBack }
                        }

                        Text {
                            anchors.centerIn: parent
                            text:  "⚙"
                            color: configDrawer._open
                                   ? root.accentColor
                                   : (gearArea.containsMouse ? "white" : "#A0FFFFFF")
                            font.pixelSize: Math.round(parent.height * 0.65)
                            Behavior on color { ColorAnimation { duration: 150 } }
                        }

                        MouseArea {
                            id: gearArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape:  Qt.PointingHandCursor
                            onClicked:    configDrawer.toggle()
                        }

                        ToolTip.visible: gearArea.containsMouse
                        ToolTip.text:    "Theme Settings  (Alt+S)"
                        ToolTip.delay:   600
                    }

                    ImageButton {
                        id: rebootButton
                        height:  parent.height
                        source:  "components/resources/reboot.svg"
                        visible: sddm.canReboot
                        onClicked: sddm.reboot()
                        KeyNavigation.backtab: loginButton
                        KeyNavigation.tab:     shutdownButton
                    }

                    ImageButton {
                        id: shutdownButton
                        height:  parent.height
                        source:  "components/resources/shutdown.svg"
                        visible: sddm.canPowerOff
                        onClicked: sddm.powerOff()
                        KeyNavigation.backtab: rebootButton
                        KeyNavigation.tab:     sessionCombo
                    }
                }
            }
        }
    }

    // ─────────────────────────────────────────────────────────────────────
    //  CONFIG DRAWER   (z 10)
    //
    //  Slides in from the left edge.  Receives the persist Settings
    //  object so it can read and write all properties directly.
    //  The reloadPlaylist/reloadBackdrop function references allow
    //  hot-swapping without needing parent property hacks.
    // ─────────────────────────────────────────────────────────────────────
    ConfigDrawer {
        id: configDrawer
        z: 10
        anchors {
            top:    parent.top
            left:   parent.left
            bottom: parent.bottom
        }

        settings:         persist
        reloadPlaylist:   root._reloadPlaylist
        reloadBackdrop:   root._reloadBackdrop
        updateBackdropFromSettings: root._updateBackdropFromSettings
        loginFocusTarget: uiLoader.item
    }

    // ─────────────────────────────────────────────────────────────────────
    //  PRIVATE HELPER FUNCTIONS
    // ─────────────────────────────────────────────────────────────────────

    function _revealUI() {
        root.uiVisible = true
    }

    function _focusAppropriateInput() {
        if (uiLoader.item && typeof uiLoader.item.focusAppropriateInput === "function") {
            uiLoader.item.focusAppropriateInput()
        }
    }

    function _parseM3u(rawText) {
        var lines   = rawText.split('\n')
        var entries = []
        for (var i = 0; i < lines.length; i++) {
            var line = lines[i].trim()
            if (line.length > 0 && line.charAt(0) !== '#') {
                entries.push(line)
            }
        }
        return entries
    }

    function _shuffleArray(arr) {
        for (var i = arr.length - 1; i > 0; i--) {
            var j   = Math.floor(Math.random() * (i + 1))
            var tmp = arr[i]
            arr[i]  = arr[j]
            arr[j]  = tmp
        }
    }

    // ─────────────────────────────────────────────────────────────────────
    //  _applyResolutionCap(entries) → entries             [NEW v4]
    //
    //  URL rewriter injected into every playlist parse path.
    //
    //  When the effective performance level is "low" (either because
    //  performanceMode === "low", or because performanceMode === "auto"
    //  and this screen is ≤ 1920 px wide), every Apple Aerial CDN URL
    //  that contains a 4K variant token is rewritten to its 2K equivalent:
    //
    //    _4K_SDR_HEVC.mov  →  _2K_SDR_HEVC.mov
    //    _4K_HEVC.mov      →  _2K_HEVC.mov
    //
    //  All other URLs are returned unchanged.  This means:
    //    • Custom local-file playlists are unaffected.
    //    • Third-party CDN URLs without the Apple Aerial naming scheme
    //      are passed through.
    //    • Already-2K URLs are a no-op.
    //
    //  Called after _parseM3u() / _loadM3u() so it always operates on
    //  the resolved, shuffled entry list — never on raw M3U text.
    //
    //  Returns the (possibly modified) array in-place for convenience.
    // ─────────────────────────────────────────────────────────────────────
    function _applyResolutionCap(entries) {
        // Resolve the effective performance level for this screen instance.
        // "auto" uses Screen.width (each Main.qml instance gets its own
        // Screen context, so a 1440p primary and a 1080p secondary resolve
        // independently — 1440p keeps 2K from day.m3u as-is, while if 4K
        // was in the playlist the 1080p screen would downgrade it).
        if (!root._isLowPerf) {
            // "high" mode or "auto" on a wide screen — no rewriting needed
            return entries
        }

        for (var i = 0; i < entries.length; i++) {
            var e = entries[i]
            // Match both naming conventions present in the Apple Aerial CDN:
            //   DB_D001_C001_4K_SDR_HEVC.mov   (newer naming scheme)
            //   comp_*_SDR_4K_HEVC.mov          (older naming scheme)
            // The replace calls are intentionally simple string substitutions,
            // not regex, to avoid escaping pitfalls with URL characters.
            if (e.indexOf("_4K_SDR_HEVC.mov") !== -1) {
                e = e.split("_4K_SDR_HEVC.mov").join("_2K_SDR_HEVC.mov")
            } else if (e.indexOf("_4K_HEVC.mov") !== -1) {
                e = e.split("_4K_HEVC.mov").join("_2K_HEVC.mov")
            }
            entries[i] = e
        }

        console.log("[AuroraGreeter] ResolutionCap applied (",
                    root.performanceMode, "/ screen", Screen.width, "x", Screen.height,
                    "):", entries.length, "URLs processed")
        return entries
    }

    function _loadM3u(resolvedUrl) {
        var xhr = new XMLHttpRequest()
        xhr.open("GET", resolvedUrl, false /* synchronous */)
        try {
            xhr.send()
        } catch (e) {
            console.warn("[AuroraGreeter] XHR exception loading playlist:", resolvedUrl, e)
            return []
        }
        var ok = (xhr.status === 0 || xhr.status === 200)
        if (!ok) {
            console.warn("[AuroraGreeter] Playlist HTTP error (", xhr.status, "):", resolvedUrl)
            return []
        }
        var entries = _parseM3u(xhr.responseText)
        if (entries.length === 0) {
            console.warn("[AuroraGreeter] Playlist parsed but contains no entries:", resolvedUrl)
            return []
        }
        // [v4] Apply resolution cap before returning.  Must happen after
        // parsing but before the caller uses the entries, so every code
        // path that calls _loadM3u() gets capped URLs automatically.
        _applyResolutionCap(entries)
        return entries
    }

    // ── Video mode: activate image fallback on MediaPlayer failure ────────
    function _activateImageFallback() {
        videoSurface.opacity  = 0
        fallbackImage.opacity = 1.0
    }

    // ─────────────────────────────────────────────────────────────────────
    //  _reloadPlaylist(resolvedUrl) — VIDEO MODE hot-swap
    //
    //  Called by ConfigDrawer when the user picks a new video playlist.
    //  Fades the VideoOutput out, replaces the MediaPlayer source, then
    //  lets onMediaStatusChanged fade back in once the first frame buffers.
    //  Resolution cap is applied to entries via _loadM3u().
    // ─────────────────────────────────────────────────────────────────────
    // ─────────────────────────────────────────────────────────────────────
    //  _reloadPlaylist(rawUrl)
    //
    //  rawUrl may be a relative path (e.g. "playlists/day.m3u") or an already
    //  absolute file:// / http:// URL.  We always re-resolve it here in
    //  Main.qml's own context so paths relative to the theme root work
    //  regardless of which component called us.
    // ─────────────────────────────────────────────────────────────────────
    function _reloadPlaylist(rawUrl) {
        // Re-resolve in Main.qml context so relative paths ("playlists/Background.mp4")
        // work even when called from ConfigDrawer (which is in components/).
        var resolvedUrl = Qt.resolvedUrl(rawUrl.toString())
        var urlStr = resolvedUrl.toString().toLowerCase()
        var isM3U  = (urlStr.indexOf('.m3u') !== -1)

        console.log("[Aurora] _reloadPlaylist — url:", resolvedUrl.toString().split("/").pop(),
                    "| isM3U:", isM3U, "| perf:", root.performanceMode)

        // Signal reload-in-progress so onMediaStatusChanged suppresses
        // the spurious NoMedia → _activateImageFallback() call that fires
        // between backgroundVideo.stop() and the new source taking effect.
        root._videoReloading = true

        // Fade out the current frame gracefully before touching the pipeline.
        videoSurface.opacity = 0

        if (isM3U) {
            var entries = _loadM3u(resolvedUrl)   // resolution cap applied inside
            if (entries.length === 0) {
                console.warn("[Aurora] Playlist empty — keeping current source.")
                root._videoReloading = false
                videoSurface.opacity = 1.0
                return
            }
            console.log("[Aurora] Playlist loaded:", entries.length, "entries. First:",
                        entries[0].toString().split("/").pop())
            root.playlistEntries = entries
            root.playlistIndex   = 0
            backgroundVideo.stop()
            backgroundVideo.source = entries[0]
        } else {
            // Direct video file — apply resolution cap to single-entry array.
            var single = [ resolvedUrl.toString() ]
            _applyResolutionCap(single)
            console.log("[Aurora] Direct video source:", single[0].toString().split("/").pop())
            root.playlistEntries = single
            root.playlistIndex   = 0
            backgroundVideo.stop()
            backgroundVideo.source = single[0]
        }

        // play() must be deferred so Qt6's internal pipeline state machine
        // finishes processing the source assignment before we request playback.
        Qt.callLater(function() {
            console.log("[Aurora] Calling backgroundVideo.play() — src:",
                        backgroundVideo.source.toString().split("/").pop())
            backgroundVideo.play()
        })
        // videoSurface.opacity animates back to 1.0 when MediaPlayer.BufferedMedia
        // fires in onMediaStatusChanged.  _videoReloading is cleared there too.
    }

    // ─────────────────────────────────────────────────────────────────────
    //  _reloadBackdrop(type, resolvedUrl) — MULTI-MODE hot-swap
    //
    //  Called by ConfigDrawer when:
    //    (a) the user changes activeBackgroundType, OR
    //    (b) the user picks a new image/slideshow source, OR
    //    (c) the user changes performanceMode (so the playlist is
    //        re-parsed with the new resolution cap setting).
    //
    //  type:        "video" | "image" | "slideshow" | "color"
    //  resolvedUrl: Qt.resolvedUrl() result for the media source.
    //               May be "" for "color" mode (no source needed).
    // ─────────────────────────────────────────────────────────────────────
    function _reloadBackdrop(type, rawUrl) {
        // Re-resolve in Main.qml context so relative paths work when this
        // function is called from ConfigDrawer (components/ subdir).
        // Absolute file:// and http:// URLs pass through unchanged.
        var resolvedUrl = Qt.resolvedUrl(rawUrl.toString())

        console.log("[Aurora] _reloadBackdrop — type:", type,
                    "| url:", rawUrl.toString().split("/").pop(),
                    "| current playbackState:", backgroundVideo.playbackState)

        // ── 1. Stop the slideshow timer if it was running ─────────────────
        if (slideshowTimer.running) {
            slideshowTimer.stop()
            console.log("[Aurora] Slideshow timer stopped")
        }

        // ── 2a. Switching TO video: do NOT stop/clear the existing player ──
        //
        //  Setting backgroundVideo.source = "" between stop() and the new
        //  source assignment triggers a MediaPlayer.NoMedia status signal.
        //  In onMediaStatusChanged that was calling _activateImageFallback(),
        //  which permanently blanked the video surface.  By skipping the
        //  source-clear when we are staying in (or entering) video mode, we
        //  let _reloadPlaylist() manage the full pipeline lifecycle with a
        //  single clean stop → new-source → callLater(play) sequence.
        if (type === "video") {
            // Just fade out the image layers; _reloadPlaylist handles the video.
            fallbackImage.opacity        = 0
            slideshowBufferImage.opacity = 0
            root._ssEntries = []
            root._ssIndex   = 0
            root._ssFront   = true
            _reloadPlaylist(resolvedUrl)
            return
        }

        // ── 2b. Switching AWAY from video: clean up the video pipeline ────
        if (backgroundVideo.playbackState !== MediaPlayer.StoppedState) {
            videoSurface.opacity = 0
            backgroundVideo.stop()
            backgroundVideo.source = ""
            console.log("[Aurora] Video pipeline torn down (switching to", type, ")")
        }

        // Reset all image layers before activating the new mode.
        fallbackImage.opacity        = 0
        slideshowBufferImage.opacity = 0
        root._ssEntries = []
        root._ssIndex   = 0
        root._ssFront   = true

        // ── 3. Start the correct non-video pipeline ───────────────────────
        switch (type) {
            case "color":
                // solidBlack.color is bound to root.backgroundColor — auto-updates.
                console.log("[Aurora] Backdrop mode → color:", root.backgroundColor)
                break

            case "image":
                console.log("[Aurora] Backdrop mode → image:", resolvedUrl.toString().split("/").pop())
                _activateStaticImage(resolvedUrl)
                break

            case "slideshow":
                console.log("[Aurora] Backdrop mode → slideshow:", resolvedUrl.toString().split("/").pop())
                _initSlideshow(resolvedUrl)
                break

            default:
                console.warn("[Aurora] Unknown backdrop type:", type)
                break
        }
    }

    // ─────────────────────────────────────────────────────────────────────
    //  _activateStaticImage(resolvedUrl)
    //
    //  Loads a single image (or the first entry of an .m3u image playlist)
    //  into fallbackImage and fades it in.
    // ─────────────────────────────────────────────────────────────────────
    function _activateStaticImage(resolvedUrl) {
        var urlStr = resolvedUrl.toString().toLowerCase()
        var isM3U  = (urlStr.indexOf('.m3u') !== -1)

        var imagePath = resolvedUrl

        if (isM3U) {
            var entries = _loadM3u(resolvedUrl)
            if (entries.length === 0) {
                console.warn("[AuroraGreeter] Image playlist empty — using solid black.")
                return
            }
            imagePath = entries[0]
        }

        var pathStr = imagePath.toString()

        // Qt QML Image does not re-fire onStatusChanged if source is set to
        // the same URL that is already loaded (and cache: false only prevents
        // disk-cache, not the in-process source-change guard).
        // Work-around: if the source is already this path AND already Ready,
        // reveal the image directly.  Otherwise clear-then-assign to force a
        // fresh load cycle and a new onStatusChanged emission.
        if (fallbackImage.source.toString() === pathStr) {
            if (fallbackImage.status === Image.Ready) {
                // Already loaded — just reveal it.
                console.log("[Aurora] Image already ready, revealing directly:",
                            pathStr.split("/").pop())
                fallbackImage.opacity = 1.0
            } else {
                // Same URL but not yet ready — clear first to force a reload.
                fallbackImage.source = ""
                fallbackImage.source = pathStr
            }
        } else {
            fallbackImage.source = pathStr
        }
        // onStatusChanged handles the opacity reveal for the async case.
    }

    // ─────────────────────────────────────────────────────────────────────
    //  _initSlideshow(resolvedUrl)
    //
    //  Parses an .m3u playlist of image paths (or takes a single image
    //  URL), populates _ssEntries, loads the first image into
    //  fallbackImage as the initial front, and starts the slideshow timer.
    //  Resolution cap is applied automatically via _loadM3u().
    // ─────────────────────────────────────────────────────────────────────
    function _initSlideshow(resolvedUrl) {
        var urlStr = resolvedUrl.toString().toLowerCase()
        var isM3U  = (urlStr.indexOf('.m3u') !== -1)

        var entries = []
        if (isM3U) {
            entries = _loadM3u(resolvedUrl)   // resolution cap applied inside
        } else {
            entries = [ resolvedUrl.toString() ]
        }

        if (entries.length === 0) {
            console.warn("[AuroraGreeter] Slideshow playlist empty — nothing to display.")
            return
        }

        // Store the parsed entry list and reset counters
        root._ssEntries = entries
        root._ssIndex   = 0
        root._ssFront   = true   // fallbackImage starts as the visible front

        // Load the first image into fallbackImage (the initial front layer).
        // Same cached-source workaround as _activateStaticImage: if the source
        // is already set to this URL and already Ready, Qt won't re-fire
        // onStatusChanged, so we reveal directly.  Otherwise clear-then-assign.
        var firstPath = entries[0].toString()
        if (fallbackImage.source.toString() === firstPath) {
            if (fallbackImage.status === Image.Ready) {
                fallbackImage.opacity = 1.0
            } else {
                fallbackImage.source  = ""
                fallbackImage.source  = firstPath
                // onStatusChanged (with _modeSlideshow && _ssFront guard) reveals it
            }
        } else {
            fallbackImage.source  = firstPath
            // onStatusChanged reveals it if async; set directly if somehow already Ready
            if (fallbackImage.status === Image.Ready)
                fallbackImage.opacity = 1.0
        }

        // Ensure the back-buffer starts hidden
        slideshowBufferImage.opacity = 0


        // Start cycling only when there are multiple images to rotate
        if (entries.length > 1) {
            slideshowTimer.start()
        }

        console.log("[AuroraGreeter] Slideshow initialised:", entries.length, "images,",
                    "interval:", root.slideshowInterval, "s")
    }

    // ─────────────────────────────────────────────────────────────────────
    //  _advanceSlideshow()
    //
    //  Called by slideshowTimer.onTriggered.  Advances to the next image
    //  in _ssEntries and loads it into the current back-buffer element.
    //  The crossfade is triggered by the onStatusChanged Connections
    //  (at the slideshowBufferImage and fallbackImage handlers above)
    //  once the back-buffer finishes decoding the image.
    // ─────────────────────────────────────────────────────────────────────
    function _advanceSlideshow() {
        if (root._ssEntries.length === 0) return

        // Advance the index, wrapping around at the end
        root._ssIndex = (root._ssIndex + 1) % root._ssEntries.length
        var nextPath = root._ssEntries[root._ssIndex]

        if (root._ssFront) {
            // fallbackImage is the current front; load next into slideshowBufferImage.
            // Crossfade triggers automatically via Connections { target: slideshowBufferImage }
            slideshowBufferImage.source = nextPath
        } else {
            // slideshowBufferImage is the current front; load next into fallbackImage.
            // Crossfade triggers via Connections { target: fallbackImage } below.
            fallbackImage.source = nextPath
        }
    }

    // ─────────────────────────────────────────────────────────────────────
    //  FALLBACK IMAGE STATUS HANDLER (back-buffer when _ssFront === false)
    //
    //  When fallbackImage is acting as the back-buffer (i.e. _ssFront is
    //  false, meaning slideshowBufferImage is the current front), we need
    //  to trigger the crossfade when fallbackImage finishes loading.
    // ─────────────────────────────────────────────────────────────────────
    Connections {
        target: fallbackImage

        function onStatusChanged() {
            if (!root._modeSlideshow)       return
            if (root._ssFront)              return   // handled by image's own onStatusChanged
            if (fallbackImage.status !== Image.Ready) return

            // fallbackImage (back) is ready → start crossfade:
            // fade out slideshowBufferImage (the current front)
            slideshowBufferImage.opacity = 0
            _swapSlideshowLayers.start()
        }
    }

    // ─────────────────────────────────────────────────────────────────────
    //  _initPlayback(rawVideoPath, rawImagePath)
    //
    //  Initialises the correct rendering pipeline on first boot based on
    //  the persisted activeBackgroundType.  Called from Component.onCompleted.
    //  Resolution cap is applied automatically via _loadM3u().
    // ─────────────────────────────────────────────────────────────────────
    function _initPlayback(rawVideoPath, rawImagePath) {
        // Always set a fallback image source (used by video mode as a
        // last-resort fallback and by image mode as the primary source).
        if (root.activeBackgroundType === "color") {
            _activateImageFallback() // Fades out video, lets solid color render
            return
    	}
	fallbackImage.source = Qt.resolvedUrl(rawImagePath)

        if (!root.showBackground) return

        var type = root.activeBackgroundType

        if (type === "color") {
            // solidBlack.color is already bound — nothing else to do.
            console.log("[AuroraGreeter] Init → color mode, bg:", root.backgroundColor)
            return
        }

        if (type === "image") {
            // Display the image immediately; onStatusChanged will reveal it.
            // (fallbackImage.source already set above)
            console.log("[AuroraGreeter] Init → image mode:", rawImagePath)
            return
        }

        if (type === "slideshow") {
            var ssUrl = Qt.resolvedUrl(rawImagePath)
            _initSlideshow(ssUrl)
            console.log("[AuroraGreeter] Init → slideshow mode:", rawImagePath)
            return
        }

        // Default: "video" mode — resolution cap applied inside _loadM3u()
        var resolvedVideo = Qt.resolvedUrl(rawVideoPath)
        var videoStr      = resolvedVideo.toString().toLowerCase()
        var isM3U         = (videoStr.indexOf('.m3u') !== -1)

        if (isM3U) {
            var entries = _loadM3u(resolvedVideo)
            if (entries.length === 0) {
                console.warn("[AuroraGreeter] Empty playlist — falling back to image.")
                _activateImageFallback()
                return
            }
            root.playlistEntries = entries
            root.playlistIndex   = 0
            backgroundVideo.source = entries[0]
        } else {
            var single = [ resolvedVideo.toString() ]
            _applyResolutionCap(single)
            root.playlistEntries = single
            root.playlistIndex   = 0
            backgroundVideo.source = single[0]
        }

        backgroundVideo.play()
        console.log("[AuroraGreeter] Init → video mode:", rawVideoPath,
                    "| perf:", root.performanceMode,
                    "| effective:", root._isLowPerf ? "low (2K)" : "high")
    }
    // ─────────────────────────────────────────────────────────────────────
    //  MULTI-SCREEN SETTINGS SYNC                                      [v6]
    //
    //  Problem: Each monitor runs its own Main.qml instance sharing the
    //  same QML engine but with separate QtObject instances. When the
    //  user changes a setting via ConfigDrawer on monitor A, it needs to
    //  propagate to monitors B and C immediately.
    //
    //  Solution: A shared QML Singleton (ThemeState) in-memory channel.
    //  The primary monitor binds ThemeState properties to its local settings,
    //  and auxiliary monitors bind their local settings to ThemeState properties.
    //  This triggers real-time updates and media pipeline reloads instantly
    //  without relying on file polling or I/O access.
    // ─────────────────────────────────────────────────────────────────────


    // ─────────────────────────────────────────────────────────────────────
    //  MULTI-SCREEN SETTINGS SYNC                                      [v6]
    //
    //  Problem: Each monitor runs its own Main.qml instance under separate
    //  QQmlEngine instances. No in-memory state or singletons are shared.
    //
    //  Solution: A lightweight polling Timer on every NON-PRIMARY screen
    //  re-reads the settings JSON file (with fallback path resolution)
    //  every 400 ms and, if it detects changes, reloads its local pipeline.
    // ─────────────────────────────────────────────────────────────────────
    property bool _isReady: false

    Timer {
        id:       settingsSyncTimer
        interval: 400
        repeat:   true
        running:  !isPrimary   // only non-primary screens need to poll

        onTriggered: {
            var xhr = new XMLHttpRequest()
            xhr.open("GET", persist._configPath, false)
            try { xhr.send() } catch(e) {
                return
            }
            if (xhr.status !== 0 && xhr.status !== 200) return
            if (!xhr.responseText || xhr.responseText.trim() === "") return

            var data = persist._parseIni(xhr.responseText)

            // ── Detect every media-relevant change ────────────────────────
            var bgChanged    = (typeof data.activeBackgroundType  === "string"  &&
                                data.activeBackgroundType  !== persist.activeBackgroundType)
            var plChanged    = (typeof data.activePlaylist        === "string"  &&
                                data.activePlaylist        !== persist.activePlaylist)
            var msChanged    = (typeof data.activeMediaSource     === "string"  &&
                                data.activeMediaSource     !== persist.activeMediaSource)
            var pmChanged    = (typeof data.performanceMode       === "string"  &&
                                data.performanceMode       !== persist.performanceMode)
            var mmChanged    = (typeof data.activeMultiMonitorMode === "string" &&
                                data.activeMultiMonitorMode !== persist.activeMultiMonitorMode)
            var schedChanged = (typeof data.useDayNightSchedule   === "boolean" &&
                                data.useDayNightSchedule   !== persist.useDayNightSchedule)
            var colorChanged = (typeof data.backgroundColor       === "string"  &&
                                data.backgroundColor       !== persist.backgroundColor)

            // Early-exit when nothing we care about changed
            if (!bgChanged && !plChanged && !msChanged && !pmChanged &&
                !mmChanged && !schedChanged && !colorChanged) return

            // ── Sync ALL changed fields into our local persist ─────────────
            if (typeof data.activeBackgroundType   === "string")  persist.activeBackgroundType   = data.activeBackgroundType
            if (typeof data.activePlaylist         === "string")  persist.activePlaylist         = data.activePlaylist
            if (typeof data.activeMediaSource      === "string")  persist.activeMediaSource      = data.activeMediaSource
            if (typeof data.performanceMode        === "string")  persist.performanceMode        = data.performanceMode
            if (typeof data.activeMultiMonitorMode === "string")  persist.activeMultiMonitorMode = data.activeMultiMonitorMode
            if (typeof data.useDayNightSchedule    === "boolean") persist.useDayNightSchedule    = data.useDayNightSchedule
            // Visual / UI settings
            if (typeof data.accentColor            === "string")  persist.accentColor            = data.accentColor
            if (typeof data.loginCardOpacity       === "number")  persist.loginCardOpacity       = data.loginCardOpacity
            if (typeof data.backgroundColor        === "string")  persist.backgroundColor        = data.backgroundColor
            if (typeof data.slideshowInterval      === "number")  persist.slideshowInterval      = data.slideshowInterval

            // ── Restart the media pipeline for any media-relevant change ───
            if (bgChanged || plChanged || msChanged || pmChanged || schedChanged || colorChanged) {
                var syncSrc
                if (persist.useDayNightSchedule) {
                    var scheduled = _resolveScheduledMedia()
                    syncSrc = (persist.activeBackgroundType === "video")
                              ? scheduled.video
                              : scheduled.image
                } else {
                    syncSrc = (persist.activeBackgroundType === "video")
                              ? persist.activePlaylist
                              : persist.activeMediaSource
                }
                _reloadBackdrop(persist.activeBackgroundType,
                                Qt.resolvedUrl(syncSrc))
            }
        }
    }


    // ─────────────────────────────────────────────────────────────────────
    //  DAY/NIGHT SCHEDULER HELPERS
    // ─────────────────────────────────────────────────────────────────────

    // Resolves time-based background paths using system clock and theme.conf settings
    function _resolveScheduledMedia() {
        var hour     = parseInt(new Date().toLocaleTimeString(Qt.locale(), 'h'))
        var dayStart = parseInt(config.day_time_start)
        var dayEnd   = parseInt(config.day_time_end)
        var isDay    = (!isNaN(dayStart) && !isNaN(dayEnd))
                       ? (hour >= dayStart && hour <= dayEnd)
                       : true

        var videoPath = isDay ? config.background_vid_day  : config.background_vid_night
        var imagePath = isDay ? config.background_img_day  : config.background_img_night
        return { video: videoPath, image: imagePath }
    }

    // Refreshes the active backdrop mode with the correct media source from settings
    function _updateBackdropFromSettings() {
        var videoPath, imagePath
        if (persist.useDayNightSchedule) {
            var scheduled = _resolveScheduledMedia()
            videoPath = scheduled.video
            imagePath = scheduled.image
            console.log("[Aurora] Backdrop Update — Schedule mode ON. video:", videoPath, "| image:", imagePath)
        } else {
            videoPath = persist.activePlaylist
            imagePath = persist.activeMediaSource !== "" ? persist.activeMediaSource : "backgrounds/background.jpg"
            console.log("[Aurora] Backdrop Update — Schedule mode OFF (Manual). video:", videoPath, "| image:", imagePath)
        }

        var syncSrc = (persist.activeBackgroundType === "video") ? videoPath : imagePath
        _reloadBackdrop(persist.activeBackgroundType, syncSrc)
    }

    // ─────────────────────────────────────────────────────────────────────
    //  INITIALISATION
    // ─────────────────────────────────────────────────────────────────────
    Component.onCompleted: {
        // ── Load persisted user settings from disk ─────────────────────
        //  Must happen before the playlist decision tree so that
        //  persist.activePlaylist, persist.activeBackgroundType, and
        //  persist.performanceMode all reflect any saved user choices.
        persist.load()

        // ── Source selection ───────────────────────────────────────────
        var videoPath, imagePath

        if (persist.useDayNightSchedule) {
            // Time-of-day picker active
            var scheduled = _resolveScheduledMedia()
            videoPath = scheduled.video
            imagePath = scheduled.image
            console.log("[Aurora] Init — scheduling is ON. video:", videoPath, "| image:", imagePath)
        } else if (persist._loaded && persist.activePlaylist !== "") {
            // User has persisted an explicit choice — honour it.
            videoPath = persist.activePlaylist
            imagePath = persist.activeMediaSource !== ""
                        ? persist.activeMediaSource
                        : (typeof config.background_img_day !== "undefined"
                           ? config.background_img_day
                           : "backgrounds/background.jpg")
            console.log("[Aurora] Init — using saved playlist:", videoPath)
        } else {
            // First boot or user reset — use theme.conf defaults.
            var scheduled = _resolveScheduledMedia()
            videoPath = scheduled.video
            imagePath = scheduled.image
            console.log("[Aurora] Init — first boot / default. video:", videoPath, "| image:", imagePath)

            // Sync default back to persist so UI states (and reload pipelines) align
            persist.activePlaylist = videoPath
            persist.activeMediaSource = imagePath

            var cfgMM = (typeof config.multiMonitorMode !== "undefined" && config.multiMonitorMode !== "")
                        ? config.multiMonitorMode
                        : "mirror"
            persist.activeMultiMonitorMode = cfgMM
        }

        _initPlayback(videoPath, imagePath)
        _isReady = true

        // ── Autofocus — primary screen only ───────────────────────────
        if (isPrimary && config.autofocusInput === "true") {
            Qt.callLater(function() {
                _revealUI()
                _focusAppropriateInput()
            })
        }
    }
}
