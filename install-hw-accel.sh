#!/usr/bin/env bash
# ==============================================================================
#  Theme   : aurora-greeter
#  Author  : Biryukov Nikita (@execorn)
#  License : CC-BY-SA-4.0 / MIT
# ==============================================================================
#  install-hw-accel.sh — GStreamer Hardware Acceleration Configurator
#
#  Installs or removes an optimised GStreamer environment drop-in for the
#  SDDM systemd service so that Qt6 Multimedia uses hardware video decode
#  (NVDEC, VAAPI, VDPAU) rather than falling back to software decode.
#
#  On low-profile hardware (integrated GPU, old CPU) this can reduce the
#  CPU load of video decode from 40–100 % on a single core down to < 5 %,
#  while allowing a dedicated GPU to zero-copy DMA-BUF frames directly to
#  the display compositor.
#
#  Usage:
#    sudo ./install-hw-accel.sh [OPTIONS]
#
#  Options:
#    --install          Install / update the drop-in (default action)
#    --uninstall        Remove the drop-in and reload systemd
#    --status           Show current drop-in content and detected hardware
#    --dry-run          Print what would be written without making changes
#    --force-gpu TYPE   Override auto-detected GPU type: nvidia | amd | intel
#    --help             Show this help
#
#  The drop-in is written to:
#    /etc/systemd/system/sddm.service.d/99-aurora-hw-accel.conf
#
#  Idempotent — safe to re-run after hardware changes or driver updates.
#  Running --install again will regenerate the file based on current state.
#
#  Requirements:
#    • systemd (systemctl)
#    • GStreamer 1.x runtime libraries (gst-inspect-1.0 for detection)
#    • libva (vainfo for VAAPI detection)
#    • GPU-specific VA driver:
#        NVIDIA  → libva-vdpau-driver  or  libva-nvidia-driver
#        AMD     → libva-mesa-driver   (usually part of mesa-va-drivers)
#        Intel   → intel-media-va-driver  (iHD)  or  i965-va-driver  (legacy)
#
#  NOTES ON SECURITY:
#    This script requires root to write to /etc/systemd/system/sddm.service.d/.
#    It does NOT modify sddm.service itself — only a drop-in override file.
#    Run `systemctl cat sddm` after install to review the effective unit.
# =============================================================================

set -euo pipefail

# ─────────────────────────────────────────────────────────────────────────────
#  CONSTANTS
# ─────────────────────────────────────────────────────────────────────────────

readonly DROPIN_DIR="/etc/systemd/system/sddm.service.d"
readonly DROPIN_FILE="${DROPIN_DIR}/99-aurora-hw-accel.conf"
readonly DROPIN_MARKER="# managed-by: sddm-aurora-hw-accel"
readonly SCRIPT_VERSION="1.0.0"

# Vendor IDs in /sys/class/drm/card*/device/vendor
readonly VENDOR_NVIDIA="0x10de"
readonly VENDOR_AMD="0x1002"
readonly VENDOR_INTEL="0x8086"

# Colour codes (disabled automatically if not a tty)
if [[ -t 1 ]]; then
    C_RESET="\033[0m"
    C_BOLD="\033[1m"
    C_RED="\033[31m"
    C_GREEN="\033[32m"
    C_YELLOW="\033[33m"
    C_BLUE="\033[34m"
    C_CYAN="\033[36m"
    C_DIM="\033[2m"
else
    C_RESET="" C_BOLD="" C_RED="" C_GREEN="" C_YELLOW=""
    C_BLUE="" C_CYAN="" C_DIM=""
fi

# ─────────────────────────────────────────────────────────────────────────────
#  LOGGING HELPERS
# ─────────────────────────────────────────────────────────────────────────────

log_info()    { echo -e "${C_GREEN}[+]${C_RESET} $*"; }
log_warn()    { echo -e "${C_YELLOW}[!]${C_RESET} $*" >&2; }
log_error()   { echo -e "${C_RED}[✗]${C_RESET} $*" >&2; }
log_section() { echo -e "\n${C_BOLD}${C_BLUE}▸ $*${C_RESET}"; }
log_detail()  { echo -e "${C_DIM}    $*${C_RESET}"; }
log_ok()      { echo -e "${C_GREEN}[✓]${C_RESET} $*"; }

# ─────────────────────────────────────────────────────────────────────────────
#  ARGUMENT PARSING
# ─────────────────────────────────────────────────────────────────────────────

ACTION="install"
DRY_RUN=0
FORCE_GPU=""

usage() {
    cat <<EOF
${C_BOLD}Aurora Greeter — GStreamer Hardware Acceleration Installer v${SCRIPT_VERSION}${C_RESET}

Usage:
  sudo $0 [OPTIONS]

Options:
  --install          Install / update the drop-in  (default)
  --uninstall        Remove the drop-in and reload systemd
  --status           Show current state and detected hardware
  --dry-run          Print what would be written, make no changes
  --force-gpu TYPE   Override GPU auto-detection: nvidia | amd | intel
  --help             Show this help and exit

The drop-in is placed at:
  ${DROPIN_FILE}

EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --install)    ACTION="install" ;;
        --uninstall)  ACTION="uninstall" ;;
        --status)     ACTION="status" ;;
        --dry-run)    DRY_RUN=1 ;;
        --force-gpu)
            shift
            FORCE_GPU="${1:-}"
            if [[ ! "$FORCE_GPU" =~ ^(nvidia|amd|intel)$ ]]; then
                log_error "--force-gpu must be: nvidia | amd | intel"
                exit 1
            fi
            ;;
        --help|-h)    usage; exit 0 ;;
        *)
            log_error "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
    shift
done

# ─────────────────────────────────────────────────────────────────────────────
#  ROOT CHECK  (skip for --status and --dry-run)
# ─────────────────────────────────────────────────────────────────────────────

if [[ "$ACTION" != "status" && "$DRY_RUN" -eq 0 && "$(id -u)" -ne 0 ]]; then
    log_error "This script must be run as root (use sudo)."
    exit 1
fi

# ─────────────────────────────────────────────────────────────────────────────
#  HARDWARE DETECTION
# ─────────────────────────────────────────────────────────────────────────────

detect_gpus() {
    # Returns newline-separated list of detected GPU types: nvidia, amd, intel
    local gpus=()
    local vendor_file vendor_id

    for vendor_file in /sys/class/drm/card*/device/vendor; do
        [[ -r "$vendor_file" ]] || continue
        vendor_id=$(cat "$vendor_file" 2>/dev/null || true)
        case "$vendor_id" in
            "$VENDOR_NVIDIA") gpus+=("nvidia") ;;
            "$VENDOR_AMD")    gpus+=("amd")    ;;
            "$VENDOR_INTEL")  gpus+=("intel")  ;;
        esac
    done

    # Deduplicate while preserving order (bash 4+)
    local seen=()
    local gpu
    for gpu in "${gpus[@]:-}"; do
        local found=0
        local s
        for s in "${seen[@]:-}"; do [[ "$s" == "$gpu" ]] && found=1 && break; done
        [[ $found -eq 0 ]] && seen+=("$gpu")
    done

    printf '%s\n' "${seen[@]:-}"
}

detect_display_server() {
    # Returns "wayland" or "x11" based on what sddm.service actually uses.
    # Priority: explicit QT_QPA env in sddm.service > WAYLAND_DISPLAY env >
    #           XDG_SESSION_TYPE > /etc/sddm.conf > x11 (safe default).

    local sddm_env
    sddm_env=$(systemctl cat sddm 2>/dev/null | grep -i "QT_QPA_PLATFORM" | head -1 || true)

    if echo "$sddm_env" | grep -qi "wayland"; then
        echo "wayland"
        return
    fi
    if echo "$sddm_env" | grep -qi "xcb\|x11"; then
        echo "x11"
        return
    fi

    # Check SDDM config for DisplayServer
    local sddm_conf
    for sddm_conf in /etc/sddm.conf /etc/sddm.conf.d/*.conf; do
        [[ -r "$sddm_conf" ]] || continue
        if grep -qi "DisplayServer.*wayland" "$sddm_conf" 2>/dev/null; then
            echo "wayland"
            return
        fi
    done

    # Check if a Wayland compositor is the SDDM greeter backend
    if systemctl cat sddm 2>/dev/null | grep -qi "wl-compositor\|kwin_wayland\|weston"; then
        echo "wayland"
        return
    fi

    echo "x11"
}

detect_vaapi_driver() {
    # Given a GPU type string, return the correct LIBVA_DRIVER_NAME value.
    local gpu_type="$1"
    case "$gpu_type" in
        nvidia)
            # Prefer the modern direct-NVDEC VA driver over the legacy VDPAU bridge
            if [[ -f /usr/lib/dri/nvidia_drv_video.so || \
                  -f /usr/lib64/dri/nvidia_drv_video.so || \
                  -f /usr/lib/x86_64-linux-gnu/dri/nvidia_drv_video.so ]]; then
                echo "nvidia"
            elif vainfo 2>/dev/null | grep -qi "NVDEC\|nvidia"; then
                echo "nvidia"
            else
                # Fallback: VDPAU bridge driver (older systems)
                echo "vdpau"
            fi
            ;;
        amd)
            # Mesa Radeonsi VA driver (GCN and later)
            if [[ -f /usr/lib/dri/radeonsi_drv_video.so || \
                  -f /usr/lib64/dri/radeonsi_drv_video.so || \
                  -f /usr/lib/x86_64-linux-gnu/dri/radeonsi_drv_video.so ]]; then
                echo "radeonsi"
            else
                # Pre-GCN r600 driver
                echo "r600"
            fi
            ;;
        intel)
            # iHD (Intel Media Driver) for Gen8+ (Broadwell+)
            # i965 (VA-API Intel driver) for Gen4–7 (legacy)
            if [[ -f /usr/lib/dri/iHD_drv_video.so || \
                  -f /usr/lib64/dri/iHD_drv_video.so || \
                  -f /usr/lib/x86_64-linux-gnu/dri/iHD_drv_video.so ]]; then
                echo "iHD"
            else
                echo "i965"
            fi
            ;;
        *)
            echo ""
            ;;
    esac
}

check_gstreamer_plugin() {
    # Returns 0 if the named GStreamer plugin element exists, 1 if not.
    gst-inspect-1.0 "$1" &>/dev/null
}

probe_hw_decode_elements() {
    # Returns a list of available hardware decode element names for the given GPU.
    local gpu_type="$1"
    local available=()

    case "$gpu_type" in
        nvidia)
            check_gstreamer_plugin nvh264dec    && available+=("nvh264dec")
            check_gstreamer_plugin nvh265dec    && available+=("nvh265dec")
            check_gstreamer_plugin nvav1dec     && available+=("nvav1dec")
            check_gstreamer_plugin nvvp9dec     && available+=("nvvp9dec")
            check_gstreamer_plugin vaapidecodebin && available+=("vaapidecodebin [NVDEC via VA-API]")
            ;;
        amd)
            check_gstreamer_plugin vaapidecodebin && available+=("vaapidecodebin [AMD VA-API]")
            check_gstreamer_plugin vaapih264dec   && available+=("vaapih264dec")
            check_gstreamer_plugin vaapih265dec   && available+=("vaapih265dec")
            ;;
        intel)
            check_gstreamer_plugin vaapidecodebin && available+=("vaapidecodebin [Intel VA-API]")
            check_gstreamer_plugin vaapih264dec   && available+=("vaapih264dec")
            check_gstreamer_plugin vaapih265dec   && available+=("vaapih265dec")
            ;;
    esac

    printf '%s\n' "${available[@]:-}"
}

# ─────────────────────────────────────────────────────────────────────────────
#  DROP-IN GENERATION
#
#  The generated file sets environment variables that are injected into the
#  sddm.service process before SDDM starts the QML greeter.  Qt6 Multimedia
#  picks these up via its GStreamer backend selection logic.
#
#  Environment variable rationale:
#
#  QT_MEDIA_BACKEND=gstreamer
#    Explicitly selects the GStreamer multimedia backend.  On Linux this is
#    already the default, but distro packages sometimes override it.
#    Making it explicit protects against future Qt package changes.
#
#  GST_VAAPI_ALL_DRIVERS=1
#    Unlocks all VA-API driver implementations including the NVIDIA VA-API
#    driver (which is not whitelisted by default in some GStreamer builds).
#    Required for NVDEC decode via libva-nvidia-driver.
#
#  LIBVA_DRIVER_NAME=<driver>
#    Points libva to the correct user-space driver shared library.
#    Without this, vainfo/vaInitialize uses heuristics that often fail on
#    multi-GPU systems or after driver updates.
#
#  GST_GL_PLATFORM=egl  (X11 with EGL)
#  GST_GL_PLATFORM=wayland  (Wayland)
#    Selects the OpenGL windowing system platform for GStreamer GL elements.
#    EGL on X11 enables the DMA-BUF zero-copy path between the hardware
#    decoder output buffer and the VideoOutput texture — avoiding a
#    CPU-side memcpy on every frame.
#    On Wayland this is always EGL; explicit is still safer.
#
#  GST_GL_API=opengl3  (for EGL path)
#    Requests OpenGL 3.x core profile via EGL rather than GLES.  Most
#    desktop Linux GPUs expose OpenGL 3.3+ and this avoids GLES fallbacks
#    that can disable certain zero-copy optimisations.
#    On Wayland and GLES-only platforms this variable is omitted.
#
#  GST_DEBUG=0
#    Suppresses GStreamer debug output in the systemd journal.  Without
#    this, INFO-level GStreamer messages flood the SDDM log at every boot.
#    Set to "2" or higher (e.g. GST_DEBUG=vaapi:4) for troubleshooting.
#
#  QML_XHR_ALLOW_FILE_READ=1
#    Allows Qt Quick's XMLHttpRequest to read file:// URLs.  Required by
#    the theme's persistence layer to load settings.conf on startup.
# ─────────────────────────────────────────────────────────────────────────────

generate_dropin() {
    local primary_gpu="$1"
    local vaapi_driver="$2"
    local display_server="$3"

    # GL platform and API selection
    local gst_gl_platform gst_gl_api_line
    if [[ "$display_server" == "wayland" ]]; then
        gst_gl_platform="wayland"
        gst_gl_api_line=""   # Wayland always uses EGL/GLES2; omit GL API override
    else
        gst_gl_platform="egl"
        gst_gl_api_line="Environment=GST_GL_API=opengl3"
    fi

    # VAAPI driver line (omitted if blank — e.g. no VA driver detected)
    local vaapi_driver_line=""
    if [[ -n "$vaapi_driver" ]]; then
        vaapi_driver_line="Environment=LIBVA_DRIVER_NAME=${vaapi_driver}"
    fi

    cat <<DROPIN
${DROPIN_MARKER}
# Generated by: install-hw-accel.sh v${SCRIPT_VERSION}
# Generated on: $(date -u '+%Y-%m-%dT%H:%M:%SZ')
# Primary GPU:  ${primary_gpu}
# Display:      ${display_server}
# VA driver:    ${vaapi_driver:-none detected}
#
# Remove this file or run:  sudo ./install-hw-accel.sh --uninstall
# Regenerate:               sudo ./install-hw-accel.sh --install

[Service]

# ── Qt6 Multimedia backend ─────────────────────────────────────────────────
# Explicitly select the GStreamer backend (default on Linux but be explicit).
Environment=QT_MEDIA_BACKEND=gstreamer

# ── VA-API / NVDEC hardware decode ────────────────────────────────────────
# Unlock all VA-API driver implementations, including NVIDIA's direct backend.
Environment=GST_VAAPI_ALL_DRIVERS=1
${vaapi_driver_line}

# ── GStreamer GL / DMA-BUF zero-copy path ─────────────────────────────────
# Select the correct GL windowing platform for zero-copy frame delivery.
# EGL on X11: decoded frames go GPU→compositor via DMA-BUF, skipping CPU RAM.
Environment=GST_GL_PLATFORM=${gst_gl_platform}
${gst_gl_api_line}

# ── GStreamer logging ──────────────────────────────────────────────────────
# Silence GStreamer INFO messages from flooding the sddm journal.
# Change to GST_DEBUG=vaapi:4 or GST_DEBUG=3 for hardware decode debugging.
Environment=GST_DEBUG=0

# ── Qt XHR file access ─────────────────────────────────────────────────────
# Required by the theme's persistence layer (settings.conf read).
Environment=QML_XHR_ALLOW_FILE_READ=1
DROPIN
}

# ─────────────────────────────────────────────────────────────────────────────
#  ACTION: STATUS
# ─────────────────────────────────────────────────────────────────────────────

action_status() {
    log_section "Hardware Detection"

    # GPU detection
    local gpus=()
    mapfile -t gpus < <(detect_gpus)

    if [[ ${#gpus[@]} -eq 0 ]]; then
        log_warn "No recognised GPUs found in /sys/class/drm"
    else
        log_info "GPUs detected:"
        local gpu
        for gpu in "${gpus[@]}"; do
            local vadrv
            vadrv=$(detect_vaapi_driver "$gpu")
            log_detail "${gpu^^}  (VA driver: ${vadrv:-not found})"

            local elems=()
            mapfile -t elems < <(probe_hw_decode_elements "$gpu")
            if [[ ${#elems[@]} -gt 0 ]]; then
                local e
                for e in "${elems[@]}"; do
                    log_detail "  ✓ GStreamer element: $e"
                done
            else
                log_detail "  ✗ No hardware GStreamer decode elements found"
                log_detail "    Install: gstreamer1.0-vaapi  or  gstreamer1.0-plugins-bad (nvcodec)"
            fi
        done
    fi

    # vainfo
    echo ""
    log_info "VA-API driver info (vainfo):"
    if command -v vainfo &>/dev/null; then
        vainfo 2>&1 | head -8 | while IFS= read -r line; do
            log_detail "$line"
        done
    else
        log_warn "vainfo not found — install libva-utils to verify VA-API"
    fi

    # Display server
    local ds
    ds=$(detect_display_server)
    echo ""
    log_info "Display server detected: ${C_CYAN}${ds}${C_RESET}"

    # Drop-in status
    echo ""
    log_section "Drop-in Status"
    if [[ -f "$DROPIN_FILE" ]]; then
        if grep -q "$DROPIN_MARKER" "$DROPIN_FILE" 2>/dev/null; then
            log_ok "Drop-in managed by this script: ${C_CYAN}${DROPIN_FILE}${C_RESET}"
        else
            log_warn "Drop-in exists but was NOT created by this script: ${DROPIN_FILE}"
        fi
        echo ""
        echo -e "${C_DIM}────────── current drop-in content ──────────${C_RESET}"
        cat "$DROPIN_FILE"
        echo -e "${C_DIM}─────────────────────────────────────────────${C_RESET}"
    else
        log_warn "No drop-in installed at: ${DROPIN_FILE}"
        log_info "Run: sudo $0 --install"
    fi

    # Effective sddm.service environment (merged)
    echo ""
    log_section "Effective sddm.service Environment"
    if command -v systemctl &>/dev/null; then
        systemctl cat sddm 2>/dev/null \
            | grep -E "^Environment=" \
            | while IFS= read -r line; do
                log_detail "$line"
              done || log_warn "Could not read sddm.service (is systemd running?)"
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
#  ACTION: UNINSTALL
# ─────────────────────────────────────────────────────────────────────────────

action_uninstall() {
    log_section "Uninstalling GStreamer HW Accel Drop-in"

    if [[ ! -f "$DROPIN_FILE" ]]; then
        log_warn "Drop-in not found: ${DROPIN_FILE}  (nothing to remove)"
        return 0
    fi

    if ! grep -q "$DROPIN_MARKER" "$DROPIN_FILE" 2>/dev/null; then
        log_error "Drop-in at ${DROPIN_FILE} was NOT created by this script."
        log_error "Remove it manually to avoid accidental damage."
        exit 1
    fi

    if [[ "$DRY_RUN" -eq 1 ]]; then
        log_warn "[DRY RUN] Would remove: ${DROPIN_FILE}"
        log_warn "[DRY RUN] Would run: systemctl daemon-reload"
        return 0
    fi

    rm -f "$DROPIN_FILE"
    log_ok "Removed: ${DROPIN_FILE}"

    # Remove the drop-in directory if it's now empty and we created it
    if [[ -d "$DROPIN_DIR" ]] && [[ -z "$(ls -A "$DROPIN_DIR")" ]]; then
        rmdir "$DROPIN_DIR" 2>/dev/null || true
    fi

    systemctl daemon-reload
    log_ok "systemctl daemon-reload  ✓"
    log_info "The change takes effect on the next SDDM restart."
}

# ─────────────────────────────────────────────────────────────────────────────
#  ACTION: INSTALL
# ─────────────────────────────────────────────────────────────────────────────

action_install() {
    log_section "Detecting Hardware"

    # ── GPU detection ─────────────────────────────────────────────────────
    local gpus=()
    mapfile -t gpus < <(detect_gpus)

    local primary_gpu=""
    local vaapi_driver=""

    if [[ -n "$FORCE_GPU" ]]; then
        primary_gpu="$FORCE_GPU"
        log_info "GPU override: ${C_BOLD}${primary_gpu^^}${C_RESET}  (--force-gpu)"
    elif [[ ${#gpus[@]} -eq 0 ]]; then
        log_warn "No recognised GPU found in /sys/class/drm/card*/device/vendor"
        log_warn "VA-API configuration will be omitted — software decode will be used."
        primary_gpu="unknown"
    else
        # Priority: NVIDIA > AMD > Intel
        # On hybrid systems the discrete GPU should be the decoder.
        local gpu
        for gpu in "${gpus[@]}"; do
            case "$gpu" in
                nvidia) primary_gpu="nvidia"; break ;;
                amd)    [[ -z "$primary_gpu" ]] && primary_gpu="amd"  ;;
                intel)  [[ -z "$primary_gpu" ]] && primary_gpu="intel" ;;
            esac
        done
        log_info "GPUs detected: ${gpus[*]}"
        log_info "Primary GPU selected: ${C_BOLD}${primary_gpu^^}${C_RESET}"
        if [[ ${#gpus[@]} -gt 1 ]]; then
            log_detail "Hybrid system detected. Using ${primary_gpu^^} as the decode target."
            log_detail "Use --force-gpu to override."
        fi
    fi

    # ── VA-API driver resolution ──────────────────────────────────────────
    vaapi_driver=$(detect_vaapi_driver "$primary_gpu")
    if [[ -n "$vaapi_driver" ]]; then
        log_ok "VA-API driver: ${C_CYAN}${vaapi_driver}${C_RESET}  (LIBVA_DRIVER_NAME)"
    else
        log_warn "Could not detect a VA-API driver library for ${primary_gpu^^}."
        log_warn "Hardware decode may not work until you install the correct driver:"
        case "$primary_gpu" in
            nvidia) log_detail "  Arch: libva-nvidia-driver  or  libva-vdpau-driver" ;;
            amd)    log_detail "  Arch: mesa-va-drivers  (usually mesa or lib32-mesa)" ;;
            intel)  log_detail "  Arch: intel-media-driver  (iHD)  or  libva-intel-driver  (i965)" ;;
        esac
    fi

    # ── GStreamer element probe ───────────────────────────────────────────
    if command -v gst-inspect-1.0 &>/dev/null; then
        local elems=()
        mapfile -t elems < <(probe_hw_decode_elements "$primary_gpu")
        if [[ ${#elems[@]} -gt 0 ]]; then
            log_ok "Hardware GStreamer decode elements available:"
            local e
            for e in "${elems[@]}"; do
                log_detail "  ✓ $e"
            done
        else
            log_warn "No hardware GStreamer decode elements found."
            case "$primary_gpu" in
                nvidia) log_detail "Install: gstreamer1.0-plugins-bad (provides nvcodec)" ;;
                amd|intel) log_detail "Install: gstreamer1.0-vaapi" ;;
            esac
            log_warn "The environment variables will be written anyway — they are"
            log_warn "harmless if the plugins are installed later."
        fi
    else
        log_warn "gst-inspect-1.0 not found — skipping element probe."
    fi

    # ── Display server detection ──────────────────────────────────────────
    local display_server
    display_server=$(detect_display_server)
    log_info "Display server: ${C_CYAN}${display_server}${C_RESET}"

    # ── Generate drop-in content ──────────────────────────────────────────
    log_section "Generating Drop-in"

    local dropin_content
    dropin_content=$(generate_dropin "$primary_gpu" "$vaapi_driver" "$display_server")

    if [[ "$DRY_RUN" -eq 1 ]]; then
        echo ""
        echo -e "${C_YELLOW}[DRY RUN] Would write to: ${DROPIN_FILE}${C_RESET}"
        echo -e "${C_DIM}────────────────────────────────────────────────${C_RESET}"
        echo "$dropin_content"
        echo -e "${C_DIM}────────────────────────────────────────────────${C_RESET}"
        log_warn "[DRY RUN] No files written. Re-run without --dry-run to apply."
        return 0
    fi

    # ── Write the file ────────────────────────────────────────────────────
    log_section "Writing Drop-in"

    # Create the directory if it doesn't exist
    if [[ ! -d "$DROPIN_DIR" ]]; then
        mkdir -p "$DROPIN_DIR"
        log_ok "Created directory: ${DROPIN_DIR}"
    fi

    # Safety: if a non-managed file exists at the path, refuse to overwrite
    if [[ -f "$DROPIN_FILE" ]] && ! grep -q "$DROPIN_MARKER" "$DROPIN_FILE"; then
        log_error "A drop-in file already exists at ${DROPIN_FILE}"
        log_error "and it was NOT created by this script."
        log_error "Remove or rename it manually before running --install."
        exit 1
    fi

    printf '%s\n' "$dropin_content" > "$DROPIN_FILE"
    chmod 644 "$DROPIN_FILE"
    log_ok "Written: ${C_CYAN}${DROPIN_FILE}${C_RESET}"

    # ── Reload systemd ────────────────────────────────────────────────────
    systemctl daemon-reload
    log_ok "systemctl daemon-reload  ✓"

    # ── Summary ───────────────────────────────────────────────────────────
    echo ""
    log_section "Installation Complete"
    echo -e "${C_GREEN}Hardware acceleration drop-in installed.${C_RESET}"
    echo ""
    echo "  GPU:          ${primary_gpu^^}"
    echo "  VA driver:    ${vaapi_driver:-not configured (install VA driver)}"
    echo "  Display:      ${display_server}"
    echo "  GL platform:  $( [[ "$display_server" == "wayland" ]] && echo "wayland" || echo "egl" )"
    echo ""
    echo "Verify with:"
    echo "  sudo systemctl cat sddm          # review merged unit"
    echo "  sudo journalctl -u sddm -f       # watch logs during next login"
    echo "  vainfo                           # confirm VA-API driver"
    echo ""
    echo "The change takes effect on the next SDDM restart:"
    echo "  sudo systemctl restart sddm"
    echo ""
    log_warn "If you log out to test: ensure another session is active,"
    log_warn "or you will be dropped to a terminal with no display manager."
}

# ─────────────────────────────────────────────────────────────────────────────
#  DISPATCH
# ─────────────────────────────────────────────────────────────────────────────

echo -e "${C_BOLD}Aurora Greeter — HW Accel Configurator v${SCRIPT_VERSION}${C_RESET}"
echo ""

case "$ACTION" in
    install)   action_install   ;;
    uninstall) action_uninstall ;;
    status)    action_status    ;;
esac
