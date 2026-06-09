<div align="center">

<br/>

```
 ╔═══════════════════════════════════════════╗
   ✦  A U R O R A  G R E E T E R  ✦      
     Cinematic · Adaptive · Open Source    
 ╚═══════════════════════════════════════════╝
```

# Aurora Greeter

**A cinematic, hardware-adaptive SDDM login theme powered by cinematic video, intelligent performance scaling, and a fully-featured live configuration drawer.**

<img src="resources/preview.gif" width="750" alt="Aurora Greeter Preview" style="border-radius: 12px; border: 1px solid rgba(255,255,255,0.15); margin: 20px 0;"/>

[![Qt6](https://img.shields.io/badge/Qt-6-41cd52?logo=qt&logoColor=white)](https://qt.io)
[![SDDM](https://img.shields.io/badge/SDDM-compatible-4c8cf5?logo=linux)](https://github.com/sddm/sddm)
[![License: MIT / CC--BY--SA--4.0](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Platform: Linux](https://img.shields.io/badge/Platform-Linux-f8761f?logo=linux&logoColor=white)](https://kernel.org)

</div>

---

## ✨ Features at a Glance

| Feature | Details |
|---|---|
| 🎬 **Four backdrop modes** | Video · Static Image · Slideshow · Solid Color |
| 🚀 **Performance profiles** | Low · Auto · High — switches resolution cap and animation speed live |
| 🔀 **Smart resolution cap** | Auto-rewrites Apple Aerial 4K URLs → 2K when screen ≤ 1920 px wide |
| 🖥️ **Multi-monitor aware** | Mirror / Primary-only / Blank-auxiliary modes; all screens sync in real-time |
| ⚙️ **Live Config Drawer** | Alt+S anywhere — change playlist, backdrop, color, clock, performance instantly |
| 🛠️ **CLI companion** | `sddm-aurora-ctl` — scriptable control of every setting from terminal |
| 🎮 **HW Acceleration** | One-command NVIDIA / AMD / Intel VA-API systemd drop-in installer |
| 💾 **Persistent settings** | All choices survive reboots via `/var/lib/sddm/.config/AuroraGreeter/settings.conf` |
| 🌙 **Day/Night playlists** | Automatic time-based playlist selection with configurable hours |
| 🔤 **Fully themeable** | Clock style, font, accent color, opacity, border radius all configurable |

---

## 📸 Quick Look

> Open the live config drawer at any time with **Alt+S** (or **Super+S**).

The drawer gives you:
- **PERFORMANCE** — Low / Auto / High profile (resolution + animation quality)
- **BACKDROP STYLE** — Video / Image / Slideshow / Color
- **Playlist/Image selector** — dynamically loaded from `playlists/index.json`
- **Slideshow interval** — 5–60 s slider (only visible in slideshow mode)
- **Color picker** — 5 presets + live preview (only visible in color mode)
- **Accent color, opacity, border radius** — all live-updating

---

## 📦 Requirements

### System Core
- **Display Manager**: `sddm` (configured for Qt6 greeter support)
- **QML Runtime**: `qt6-declarative` / `qml6` modules
- **Multimedia Engine**: `qt6-multimedia` (specifically targeting GStreamer backend on Linux)
- **Video Decoding Backends**: `gstreamer1.0-plugins-good` and `gstreamer1.0-plugins-bad`

### Optional Hardware Decode
- **Intel / AMD**: `gstreamer1.0-vaapi` and `libva`
- **NVIDIA**: `nvidia-vaapi-driver` (direct NVDEC wrapper) or `libva-vdpau-driver`

> [!IMPORTANT]
> **Legacy Qt5 Dynamic Linker Crash (Exit Code 127)**:
> On modern Linux installations where legacy Qt5 packages are deprecated or uninstalled, starting SDDM can crash immediately with helper exit status 127. This occurs because SDDM launches the legacy `/usr/bin/sddm-greeter` (Qt5) binary by default if the theme configuration lacks a Qt6 identifier.
> To prevent this, this theme explicitly declares the required runtime in `metadata.desktop` via the `QtVersion=6` flag, forcing SDDM to invoke the native `/usr/bin/sddm-greeter-qt6` greeter.

---

## 🚀 Installation

### 📦 Option A — Arch Linux (AUR)

For Arch Linux users, the theme and its companion CLI command are packaged in the Arch User Repository (AUR) under the name `sddm-theme-aurora-greeter-git`.

Install it using your preferred AUR helper (e.g. `yay` or `paru`):

```bash
yay -S sddm-theme-aurora-greeter-git
```

*This automatically resolves dependencies, deploys the theme files, symlinks the control tool directly into `/usr/bin/sddm-aurora-ctl` so it can be run from anywhere, and sets up correct ownership and execution permissions.*

### 🛠️ Option B — Manual Installation (Other Distros)

```bash
# 1. Clone the repo
git clone https://github.com/execorn/aurora-greeter /path/to/aurora-greeter
cd /path/to/aurora-greeter

# 2. Run the installer script
sudo bash install.sh

# 3. (Optional but highly recommended) Enable hardware video decode
sudo /usr/share/sddm/themes/aurora-greeter/sddm-aurora-ctl hw-accel install
```

### ⚙️ Post-Installation Activation

To set SDDM to use the Aurora Greeter:

```bash
echo '[Theme]
Current=aurora-greeter' | sudo tee /etc/sddm.conf.d/aurora.conf
```

To test or apply your settings immediately, restart the SDDM service (warning: this will end your current active user session!):

```bash
sudo systemctl restart sddm
```

---

## 🛠️ Building / Testing Locally

> You do **not** need to install the theme to test it. Qt6 ships a standalone QML runtime viewer.

### Step 1 — Install test dependencies

```bash
# Arch / Manjaro
sudo pacman -S qt6-declarative qt6-multimedia gst-plugins-base gst-plugins-good

# Debian / Ubuntu / Pop!_OS
sudo apt install qml6-module-qtmultimedia qt6-multimedia-dev gstreamer1.0-plugins-good
```

### Step 2 — Run the viewer

```bash
cd /path/to/aurora-greeter

# Minimal: renders on your current display server
qml6 Main.qml

# With SDDM stub context (required for textConstants, sddm object, etc.)
QML_IMPORT_PATH=./stubs qml6 Main.qml

# Multi-monitor simulation: launch two windows concurrently:
qml6 Main.qml &
qml6 Main.qml &
```

> [!WARNING]
> **NVIDIA Proprietary Driver Crash on X11**:
> When running the local test mode on systems utilizing the Nvidia proprietary graphics driver under an X11 server, the greeter window may crash instantly inside the GLX core due to shared context negotiation failures in Qt6's default multi-threaded render loop.
> **Resolution:** Force the QML scene graph engine to run in single-threaded mode by launching the viewer with the environment override:
> ```bash
> QSG_RENDER_LOOP=basic qml6 Main.qml
> ```

---

## 🏛️ System Architecture, Integration & Limitations

To maintain professional-grade stability and reliability on production display manager setups, Aurora Greeter incorporates several architectural resolutions to common system-level integration issues:

### 1. Sandbox & Non-Privileged Audio Probe Segmentation Faults
- **The Issue:** Opening the Qt6 greeter can trigger sudden, silent segmentation faults on startup during audio format negotiation (often marked by ALSA or PipeWire library traces in the logs).
- **The Cause:** Initializing physical audio channels—even if explicitly muted in the configuration—forces the underlying multimedia engine to probe system sound cards. During the early boot phase or in non-privileged local "test-mode" environments, the active display manager process lacks access to the user-space PipeWire/WirePlumber sockets, triggering a fatal null-pointer dereference.
- **The Resolution:** For maximum stability and hardware independence, any physical audio output mapping has been completely removed from the QML media pipeline, bypassing audio system initialization checks entirely.

### 2. NVIDIA Multi-Threaded Rendering Crash on X11
- **The Issue:** On systems using the Nvidia proprietary graphics driver under an X11 (Xorg) display server, launching the greeter (or testing it locally) can cause an immediate process crash inside the Nvidia driver GLX core.
- **The Cause:** Qt6's default multi-threaded rendering engine fails to negotiate shared GLX contexts with the Nvidia driver during the early boot phase.
- **The Resolution:** Users running Nvidia under X11 must force the graphics engine to run in single-threaded mode by setting the environment variable `QSG_RENDER_LOOP=basic` at startup.

### 3. Wayland-Specific Variables Crashing the Xorg Server on Boot
- **The Issue:** Passing standard Wayland/DRM parameters to a system running SDDM under X11 causes the entire Xorg display server itself to crash on boot with a core dump inside the Nvidia GLX dispatcher.
- **The Cause:** Environment variables such as `__GLX_VENDOR_LIBRARY_NAME=nvidia` or `GBM_BACKEND=nvidia-drm` passed globally to the Xorg parent process tree confuse Xorg's internal GLVND (OpenGL Vendor Neutral Dispatch) system, causing a fatal crash during server initialization.
- **The Resolution:** If SDDM is configured to run on an X11 server, any Wayland-specific or direct rendering manager (DRM) environment variables must be stripped from the boot-level configurations.

### 4. PAM Environment Variable Scrubbing & Local File Safety
- **The Issue:** Local file reading via `XMLHttpRequest` (which this theme uses to parse `.m3u` playlists and load settings) is disabled by default in Qt6. Even if systemd unit files are configured to allow it, the theme may still load to a blank black screen.
- **The Cause:** On boot, the `sddm-helper` process executes the greeter under a PAM session, which actively scrubs all environment variables. This strips `QML_XHR_ALLOW_FILE_READ=1` and `QML_XHR_ALLOW_FILE_WRITE=1` from the active environment.
- **The Resolution:** To bypass PAM sanitization on boot, these variables must be defined directly inside SDDM's native `GreeterEnvironment` configuration directive in `/etc/sddm.conf.d/10-theme.conf` (which SDDM injects *after* PAM scrubbing), or injected globally via the PAM persistent environment (`/etc/security/pam_env.conf`), rather than relying solely on systemd service files.

### 5. Multi-Monitor "Ghost Viewport" Resolution Race Conditions
- **The Issue:** On mixed-resolution multi-monitor configurations, a primary high-resolution monitor may render two overlapping, duplicated video backgrounds (e.g., a small 1080p window floating underneath the correct 1440p login card).
- **The Cause:** If Xorg initially boots at a default fallback resolution (like 1080p) and is resized on the fly by a late-running user-space script, the Qt6 windowing system spawns a second viewport window for the new resolution instead of resizing the existing one.
- **The Resolution:** Users must configure their physical monitor geometries *before* the greeter window compiles. This is achieved by placing the exact, final multi-monitor layout setup commands (using utility commands like `xrandr`) directly inside SDDM's pre-greeter setup script: `/usr/share/sddm/scripts/Xsetup`.

---

## 🎛️ CLI Reference — `sddm-aurora-ctl`

The `sddm-aurora-ctl` script is your terminal interface to every setting. It operates on `/var/lib/sddm/.config/AuroraGreeter/settings.conf` and theme configuration files.

> [!NOTE]
> - **Arch Linux (AUR) Users**: The script is globally symlinked. You can execute `sddm-aurora-ctl` directly from any directory (e.g., `sudo sddm-aurora-ctl --help`).
> - **Manual Users**: Execute the script using its absolute path `sudo /usr/share/sddm/themes/aurora-greeter/sddm-aurora-ctl` or from within the cloned repository directory via `./sddm-aurora-ctl`.

```bash
# Show all subcommands
sddm-aurora-ctl --help
```

### Catalogue Management (`catalogue` / `cat`)
Manages `playlists/index.json` which the ConfigDrawer reads to populate its picker models.

```bash
# List all registered catalogue entries
sudo sddm-aurora-ctl catalogue list

# Add a video playlist from a directory (scans recursively, generates a .m3u, registers it)
sudo sddm-aurora-ctl catalogue add-video "My Vacation Videos" /path/to/videos/folder

# Register a single image in index.json (copies it to theme's backgrounds/ directory)
sudo sddm-aurora-ctl catalogue add-image "Sunset Skyline" /path/to/image.png

# Remove an entry from the catalogue (does not delete underlying files)
sudo sddm-aurora-ctl catalogue remove "Sunset Skyline" --type image
```

### Playlist Creation (`playlist`)
Manage custom playlists directly.

```bash
# Scan a directory recursively and create an .m3u playlist in theme's playlists/ folder
sudo sddm-aurora-ctl playlist create summer_playlist /path/to/media

# Change playback order of a playlist (shuffled or sequential)
sudo sddm-aurora-ctl playlist order summer_playlist shuffled
```

### Active Wallpaper / Backdrop Source (`wallpaper`)
Set the active background source directly.

```bash
# Set a local video file, image file, .m3u playlist, or streaming URL
sudo sddm-aurora-ctl wallpaper set /path/to/my_background.jpg
sudo sddm-aurora-ctl wallpaper set playlists/summer_playlist.m3u
sudo sddm-aurora-ctl wallpaper set https://example.com/stream.mp4
```

### Day/Night Scheduler (`scheduler`)
Configure automatic schedule-based background swapping.

```bash
# Set day mode start and end hours (24h format)
sudo sddm-aurora-ctl scheduler set-time --day-start 8 --day-end 21

# Enable/disable scheduling mode (switch between time-based and manual settings)
sudo sddm-aurora-ctl config set-theme --schedule on
sudo sddm-aurora-ctl config set-theme --schedule off
```

> [!TIP]
> In the Config Drawer GUI, you can toggle between **Scheduled** and **Manual** modes under **DAY/NIGHT SCHEDULING**. Tapping any specific playlist or wallpaper from the catalogue automatically switches the mode to **Manual** so your custom choice is played immediately.

### Theme & Aesthetics Configuration (`config`)
Modify appearance properties.

```bash
# Set performance mode (low | auto | high)
sudo sddm-aurora-ctl config set-theme --performance-mode low

# Set backdrop type (video | image | slideshow | color)
sudo sddm-aurora-ctl config set-theme --bg-type slideshow

# Set solid background color (for color mode)
sudo sddm-aurora-ctl config set-theme --bg-type color --bg-color '#1e1e2e'

# Set slideshow transition interval in seconds (5–60)
sudo sddm-aurora-ctl config set-theme --slideshow-interval 20

# Set accent color (highlight color for focus ring, pills)
sudo sddm-aurora-ctl config set-theme --accent '#cba6f7'

# Set login card background opacity (0.0–1.0)
sudo sddm-aurora-ctl config set-theme --opacity 0.75

# Set login card border radius in pixels
sudo sddm-aurora-ctl config set-theme --radius 22

# Set multi-monitor mode (mirror | primary-only | blank-auxiliary)
sudo sddm-aurora-ctl config set-theme --monitor-mode primary-only

# Toggle day/night time-based scheduling (on | off)
sudo sddm-aurora-ctl config set-theme --schedule off
```

### Hardware Acceleration (`hw-accel`)
Manage the systemd GStreamer hardware acceleration drop-in.

```bash
# Install drop-in with GPU auto-detection
sudo sddm-aurora-ctl hw-accel install

# Force a specific driver type (nvidia | amd | intel)
sudo sddm-aurora-ctl hw-accel install --force-gpu amd

# View detection details and drop-in status
sddm-aurora-ctl hw-accel status

# Remove the systemd drop-in
sudo sddm-aurora-ctl hw-accel uninstall
```

---

## 🎞️ Custom Playlists & Slideshows

Aurora Greeter supports custom `.m3u` playlists and directories for both video loops and image slideshows.

### Example: Setting up a custom image slideshow from a directory

If you have a local directory of wallpapers (e.g., `/path/to/wallpapers`) and want to use it as a slideshow:

#### Option A: Set Active Slideshow via CLI
```bash
# 1. Register the image directory (scans, copies, creates playlist, and catalogs it)
sudo sddm-aurora-ctl catalogue add-image "My Wallpapers" /path/to/wallpapers

# 2. Set the background type to slideshow and disable scheduler
sudo sddm-aurora-ctl config set-theme --bg-type slideshow --schedule off

# 3. Set the active wallpaper source to the new playlist
sudo sddm-aurora-ctl wallpaper set playlists/My_Wallpapers.m3u
```

#### Option B: Choose from the Config Drawer GUI
```bash
# 1. Register the image directory in the catalogue
sudo sddm-aurora-ctl catalogue add-image "My Wallpapers" /path/to/wallpapers
```
2. Reboot or restart SDDM to reload the greeter.
3. Open the Config Drawer (**Alt+S**), select **Slideshow** as the backdrop style, and choose **My Wallpapers** from the list!

---

## 🎨 Customizing the Clock & Login Fields

Visual layout tokens are defined in `theme.conf` (system defaults) and overridden by `/usr/share/sddm/themes/aurora-greeter/theme.conf.user` (user changes).

### Available `theme.conf` / `theme.conf.user` keys

```ini
[General]
# ── Clock & position ────────────────────────────────────────────────────────
# Fractional position of the clock center on screen (0.0–1.0)
relativePositionX=0.5
relativePositionY=0.75

# 12h or 24h clock display
clockFormat=24h          # or: 12h

# Font family for clock and login labels
displayFont="Misc Fixed"

# ── Login card ───────────────────────────────────────────────────────────────
loginCardOpacity=0.72    # transparency of the glassmorphism card (0.0–1.0)
loginCardColor=#1A000000 # ARGB hex of the card fill

# ── Glassmorphism border ─────────────────────────────────────────────────────
borderRadius=22          # corner radius in px
borderWidth=1
borderColor=#40FFFFFF    # RGBA hex of the glass border

# ── Accent color ─────────────────────────────────────────────────────────────
accentColor=#268bd2      # used on field focus rings, drawer active states

# ── UI chrome ────────────────────────────────────────────────────────────────
showLoginButton=true
showClearPasswordButton=true
showTopBar=true          # session/language/gear/reboot/shutdown bar
autofocusInput=true      # focus username field immediately on show

# ── Spacing ──────────────────────────────────────────────────────────────────
usernameLeftMargin=15
passwordLeftMargin=15

# ── Day/night schedule ────────────────────────────────────────────────────────
day_time_start=8         # hour (24h) when day playlist starts
day_time_end=21          # hour (24h) when night playlist starts
background_vid_day=playlists/Background.mp4
background_vid_night=playlists/Background.mp4
background_img_day=backgrounds/background.jpg
background_img_night=backgrounds/background.jpg
```

---

## ⚡ Performance Profiles — Deep Dive

| Profile | Resolution cap | Animation durations | Best for |
|---|---|---|---|
| **Low** | Always 2K (rewrites 4K URLs) | 150–400 ms | Integrated GPU, CPU-only decode, Raspberry Pi |
| **Auto** *(default)* | ≤ 1920 px wide → 2K, wider → playlist as-is | Full (800 ms+) | Most users — adaptive per monitor |
| **High** | Never cap — use playlist URLs | Full cinematic | Dedicated GPU with hardware HEVC decode |

Switch profile from the Config Drawer (PERFORMANCE pill) or via CLI:
```bash
sudo sddm-aurora-ctl config set-theme --performance-mode low
```

---

## 🌍 Multi-Monitor Configuration

```bash
# All screens show background + login UI
sudo sddm-aurora-ctl config set-theme --monitor-mode mirror

# Primary screen gets video + UI; others get video only
sudo sddm-aurora-ctl config set-theme --monitor-mode primary-only

# Primary gets everything; auxiliary screens are solid black (saves GPU on weak setups)
sudo sddm-aurora-ctl config set-theme --monitor-mode blank-auxiliary
```

Settings changes made in the Config Drawer are natively serialized to the INI config file (`settings.conf`) using QML's `Qt.labs.settings` component on the primary monitor. All auxiliary monitors (which run in isolated QML engines) poll this file every 400 ms via `XMLHttpRequest` GET and a lightweight custom INI parser, reloading their media pipelines in real-time when changes are detected.

---

## 🗂️ Project Structure

```
aurora-greeter/
├── Main.qml                  # Root QML scene — backdrop engine, login UI
├── theme.conf                # Default configuration values
├── theme.conf.user           # User overrides (wins over theme.conf)
├── metadata.desktop          # SDDM theme metadata
├── install.sh                # System installer
├── install-hw-accel.sh       # GStreamer HW decode drop-in installer
├── sddm-aurora-ctl           # CLI management tool (Python 3.10+)
├── backgrounds/
│   └── background.jpg        # Fallback default static image
├── playlists/
│   ├── index.json            # Dynamic settings/media catalogue definition
│   └── Background.mp4        # Bundled default 2K cinematic loop (450 MB)
└── components/
    ├── ConfigDrawer.qml      # Slide-in settings panel
    ├── Clock.qml             # Themeable clock widget
    ├── TextBox.qml           # Styled username input field
    ├── PasswordBox.qml       # Styled password input field
    ├── Button.qml            # Styled button component
    └── resources/            # Icons, SVGs
```

---

## 🔑 Keyboard Shortcuts

| Shortcut | Action |
|---|---|
| **Alt+S** | Toggle Config Drawer |
| **Super+S** | Toggle Config Drawer |
| **Enter** | Login (from username or password field) |
| **Tab** | Cycle between username → password → login button |

---

## ❓ Troubleshooting & FAQ

### Troubleshooting Table

| Symptom | Probable Cause | Corrective Action |
|---|---|---|
| SDDM fails to start; screen goes black, dynamic linker prints library missing error (Exit Code 127) | SDDM is attempting to run standard `/usr/bin/sddm-greeter` (Qt5) because of a missing Qt version directive. | Ensure `QtVersion=6` is declared in the theme's `metadata.desktop` file (this is configured by default). |
| Immediate crash / segmentation fault during audio format negotiation | The media engine is trying to initialize physical audio output lines inside a non-privileged display manager or test session. | Confirm that no `audioOutput` block is declared in the QML media pipeline. |
| Greeter crashes inside GLX core when running on NVIDIA proprietary driver + X11 | Qt6 multi-threaded rendering engine fails to negotiate shared GLX context. | Force single-threaded rendering loop by setting `QSG_RENDER_LOOP=basic` in the startup script or command execution. |
| Whole Xorg display server crashes on startup | Wayland-specific environment variables (`__GLX_VENDOR_LIBRARY_NAME`, `GBM_BACKEND`) passed to Xorg confuse the OpenGL dispatch. | Strip Wayland-specific or direct rendering manager (DRM) environment variables from boot-level configurations if running under X11. |
| The theme loads to a blank black screen, or QML's local file access via `XMLHttpRequest` fails | The `sddm-helper` PAM session scrubs environment variables like `QML_XHR_ALLOW_FILE_READ=1`. | Define the environment overrides in SDDM's native `GreeterEnvironment` directive inside `10-theme.conf` or in `/etc/security/pam_env.conf`. |
| Overlapping / double background viewports rendering on a primary high-resolution monitor | Monitor geometries changed after the window compilation, causing Qt6 to instantiate an extra `QQuickView`. | Define physical layouts using utility setup script overrides (like `xrandr`) in `/usr/share/sddm/scripts/Xsetup` before the greeter compiles. |

### FAQ

**Q: The video doesn't load — I see a black screen.**
→ Check internet connectivity. Built-in playlists stream from Apple's CDN (`sylvan.apple.com`). For offline use, create a local `.m3u` pointing to local video files or use the default `Background.mp4`.

**Q: How do I make the login panel appear?**
→ Move the mouse, press any key, or wait. The UI fades in automatically.

**Q: Can I use Wayland / SDDM-wayland?**
→ Yes. The `install-hw-accel.sh` script detects your display server and sets `QT_QPA_PLATFORM` accordingly.

**Q: The Alt+S shortcut doesn't work.**
→ Aurora Greeter uses Qt's `Shortcut` element which fires globally even when a text field has focus. If it still doesn't respond, check that your `sddm-greeter` is built against Qt6 (not Qt5).

**Q: The clock/login panel is off-center.**
→ Check `theme.conf.user` → `relativePositionX` and `relativePositionY`. Set both to `0.5` for dead-center, or use the `theme.conf` defaults.

---



## 📜 License

CC-BY-SA-4.0 / MIT © [LICENSE](LICENSE)
