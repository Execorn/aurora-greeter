#!/usr/bin/env bash
# ==============================================================================
#  Theme   : aurora-greeter
#  Author  : Biryukov Nikita (@execorn)
#  License : CC-BY-SA-4.0 / MIT
# ==============================================================================
#  What this script does (in order):
#    1.  Verifies root privilege
#    2.  Backs up any existing /usr/share/sddm/themes/aurora-greeter installation
#    3.  Deploys all theme files to /usr/share/sddm/themes/aurora-greeter/
#    4.  Sets standard filesystem permissions (dirs 755, files 644)
#    5.  Creates the sddm user's writable config directory so the QML
#        persistence layer can save ConfigDrawer choices across reboots
#    6.  Writes /etc/sddm.conf.d/10-theme.conf to activate the theme
#        AND inject GreeterEnvironment variables (GStreamer, Nvidia, XHR)
#
#  Post-mortem lessons baked into this installer:
#
#    A. Pipewire/ALSA crash — the theme's MediaPlayer has NO audioOutput
#       block, so Qt6 never negotiates an audio pipeline.  GST_AUDIOSINK=
#       fakesink is set as defense-in-depth via GreeterEnvironment.
#
#    B. Qt5 library error 127 — metadata.desktop declares QtVersion=6,
#       forcing SDDM to launch sddm-greeter-qt6 directly.
#
#    C. PAM environment scrubbing — systemd service Environment= lines
#       are stripped by PAM/sddm-helper before the greeter spawns.
#       All env vars are set via SDDM's native [General]
#       GreeterEnvironment key, which survives PAM sanitization.
#
#  Exit codes:
#    0  — success
#    1  — pre-flight check failed (no root, source dir missing, etc.)
#    2  — a filesystem operation failed (rsync, chmod, mkdir, …)
# ==============================================================================

set -euo pipefail

# ── ANSI colour palette ──────────────────────────────────────────────────────
# Each helper prints a consistently formatted, coloured status line.
readonly _RESET='\033[0m'
readonly _BOLD='\033[1m'
readonly _GREEN='\033[0;32m'
readonly _CYAN='\033[0;36m'
readonly _YELLOW='\033[0;33m'
readonly _RED='\033[0;31m'
readonly _DIM='\033[2m'
readonly _MAGENTA='\033[0;35m'

_banner() {
    echo -e ""
    echo -e "${_BOLD}${_CYAN}╔══════════════════════════════════════════════════════════════╗${_RESET}"
    echo -e "${_BOLD}${_CYAN}║        Aurora Greeter  —  System Installer                    ║${_RESET}"
    echo -e "${_BOLD}${_CYAN}║        Qt6 · Wayland · Nvidia · Arch Linux                   ║${_RESET}"
    echo -e "${_BOLD}${_CYAN}╚══════════════════════════════════════════════════════════════╝${_RESET}"
    echo -e ""
}

_step() {
    # _step <number> <description>
    echo -e "${_BOLD}${_CYAN}[${1}]${_RESET} ${_BOLD}${2}${_RESET}"
}

_ok() {
    echo -e "    ${_GREEN}✔${_RESET}  ${1}"
}

_info() {
    echo -e "    ${_DIM}ℹ${_RESET}  ${1}"
}

_warn() {
    echo -e "    ${_YELLOW}⚠${_RESET}  ${_YELLOW}${1}${_RESET}"
}

_err() {
    echo -e ""
    echo -e "    ${_RED}${_BOLD}✘  ERROR: ${1}${_RESET}" >&2
    echo -e "" >&2
}

_die() {
    # _die <exit-code> <message>
    _err "${2}"
    exit "${1}"
}

_section_done() {
    echo -e "    ${_DIM}────────────────────────────────────────────────────────────${_RESET}"
}

# ── Resolved paths (all constants — defined once, used everywhere) ────────────
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly THEME_NAME="aurora-greeter"
readonly THEME_DEST="/usr/share/sddm/themes/${THEME_NAME}"
readonly SDDM_CONF_DIR="/etc/sddm.conf.d"
readonly SDDM_CONF_FILE="${SDDM_CONF_DIR}/10-theme.conf"
readonly SDDM_CONFIG_HOME="/var/lib/sddm/.config/AuroraGreeter"
readonly SDDM_USER="sddm"
readonly SDDM_GROUP="sddm"

# ==============================================================================
#  STEP 0 — Root privilege check
# ==============================================================================
_banner

_step "0" "Verifying root privileges"

if [[ "${EUID}" -ne 0 ]]; then
    _die 1 "This script must be run as root.\n\n        Re-run with:  sudo ${BASH_SOURCE[0]}"
fi
_ok "Running as root (UID 0)"

# Sanity-check: the source directory must contain Main.qml
if [[ ! -f "${SCRIPT_DIR}/Main.qml" ]]; then
    _die 1 "Source directory does not look like the Aurora Greeter repo.\n\n        Expected:  ${SCRIPT_DIR}/Main.qml\n\n        Run this script from the root of the cloned repository."
fi
_ok "Source directory validated: ${SCRIPT_DIR}"

_section_done

# ==============================================================================
#  STEP 1 — Backup any existing installation
# ==============================================================================
_step "1" "Checking for an existing theme installation"

if [[ -d "${THEME_DEST}" ]]; then
    BACKUP_DIR="${THEME_DEST}.bak_$(date +%Y%m%d_%H%M%S)"
    _warn "Existing theme found at ${THEME_DEST}"
    _info "Creating timestamped backup → ${BACKUP_DIR}"

    if ! mv "${THEME_DEST}" "${BACKUP_DIR}"; then
        _die 2 "Failed to move existing theme to backup location.\n\n        Check permissions on /usr/share/sddm/themes/ and retry."
    fi
    _ok "Backup created: ${BACKUP_DIR}"
else
    _ok "No existing installation found — proceeding with a clean install"
fi

_section_done

# ==============================================================================
#  STEP 2 — Deploy theme files
# ==============================================================================
_step "2" "Deploying theme files to ${THEME_DEST}"

# Create the target directory structure.
if ! mkdir -p "${THEME_DEST}"; then
    _die 2 "Could not create target directory: ${THEME_DEST}"
fi
_ok "Target directory created: ${THEME_DEST}"

# rsync flags:
#   -a  — archive mode (preserves symlinks, timestamps; recursive)
#   --exclude  — skip version-control and editor artefacts that must
#                never land in the system theme directory
#   --delete   — ensures the destination mirrors the source exactly
#                (harmless on a fresh install; cleans stale files on update)
#   --info=progress2  — single-line progress counter instead of per-file spam
_info "Syncing files (excluding .git, .gitignore, install.sh, *.bak, …)"

rsync -a \
    --exclude='.git/' \
    --exclude='.gitignore' \
    --exclude='.gitmodules' \
    --exclude='*.bak' \
    --exclude='*.bak_*' \
    --exclude='install.sh' \
    --exclude='.vscode/' \
    --exclude='.idea/' \
    --exclude='__pycache__/' \
    --delete \
    --info=progress2 \
    "${SCRIPT_DIR}/" \
    "${THEME_DEST}/"

_ok "All theme files deployed to ${THEME_DEST}"
_section_done

# ==============================================================================
#  STEP 3 — Enforce filesystem permissions
# ==============================================================================
_step "3" "Setting standard filesystem permissions"

# Directories: 755 (rwxr-xr-x)  — SDDM daemon and the QML engine need to
#              traverse into sub-directories to locate component files.
# Files:       644 (rw-r--r--)  — Readable by everyone; not executable.
#
# The sddm user runs as a system account with minimal privileges.  Standard
#755/644 is sufficient for read access; the write-capable config directory
# is handled separately in Step 4.

_info "Setting directories → 755"
find "${THEME_DEST}" -type d -exec chmod 755 {} \;

_info "Setting files → 644"
find "${THEME_DEST}" -type f -exec chmod 644 {} \;

# Make the companion CLI tool executable
if [[ -f "${THEME_DEST}/sddm-aurora-ctl" ]]; then
    chmod 755 "${THEME_DEST}/sddm-aurora-ctl"
    _ok "Companion CLI tool executable set to 755"
fi

# Root owns everything in the theme directory.
chown -R root:root "${THEME_DEST}"

_ok "Ownership: root:root"
_ok "Directories: 755  |  Files: 644 (CLI tool: 755)"
_section_done

# ==============================================================================
#  STEP 4 — Create sddm-writable persistent config directory
# ==============================================================================
_step "4" "Creating persistent config store for the sddm user"

# The theme's QML persistence layer (persist.load / settingsStore in Main.qml)
# reads and writes an INI settings file.  At runtime the
# sddm system user's home is /var/lib/sddm, so the full path becomes:
#   /var/lib/sddm/.config/AuroraGreeter/settings.conf
#
# The directory must be:
#   • owned by the sddm user/group
#   • mode 750: sddm can write; group members can read; others have no access
#     (more secure than 755 for a config store containing user preferences)
#
# We use mkdir -p so the intermediate .config layer is also created if absent.

if ! mkdir -p "${SDDM_CONFIG_HOME}"; then
    _die 2 "Failed to create persistent config directory: ${SDDM_CONFIG_HOME}"
fi

# Verify the sddm system user actually exists before chowning
if ! id -u "${SDDM_USER}" &>/dev/null; then
    _warn "System user '${SDDM_USER}' not found."
    _warn "Skipping chown — you may need to set ownership manually after SDDM is installed."
else
    chown -R "${SDDM_USER}:${SDDM_GROUP}" "${SDDM_CONFIG_HOME}"
    _ok "Ownership set: ${SDDM_USER}:${SDDM_GROUP}"
fi

chmod 750 "${SDDM_CONFIG_HOME}"
_ok "Permissions: 750 (sddm rw, group r, others none)"
_ok "Persistent config directory: ${SDDM_CONFIG_HOME}"
_info "ConfigDrawer will write to: ${SDDM_CONFIG_HOME}/settings.conf"
_section_done

# ==============================================================================
#  STEP 5 — Activate theme & inject GreeterEnvironment
# ==============================================================================
_step "5" "Writing SDDM theme + environment configuration"

# /etc/sddm.conf.d/ is the recommended drop-in directory.
# Individual files here are merged by SDDM in lexicographic order.
# The prefix "10-" gives us a predictable, early position in the sort.
#
# CRITICAL ARCHITECTURAL DECISION — GreeterEnvironment vs systemd Environment=
# ─────────────────────────────────────────────────────────────────────────────
# During testing we discovered that PAM and sddm-helper actively strip ALL
# environment variables inherited from the systemd unit before spawning the
# greeter process.  This means systemd service drop-in Environment= lines
# (e.g. in /etc/systemd/system/sddm.service.d/override.conf) are silently
# discarded, causing the QML engine's XMLHttpRequest to throw a fatal
# security exception (blank black screen) because QML_XHR_ALLOW_FILE_READ
# was never set.
#
# The correct injection point is SDDM's native [General] GreeterEnvironment
# key.  SDDM parses this key itself and injects the variables directly into
# the greeter's environment AFTER PAM sanitization, guaranteeing they survive.
#
# Variable rationale:
#   QML_XHR_ALLOW_FILE_READ=1    — permit QML's XMLHttpRequest to read local
#                                   .m3u playlists and settings.conf
#   QML_XHR_ALLOW_FILE_WRITE=1   — legacy/compatibility setting for local writes
#   QT_MEDIA_BACKEND=gstreamer   — force GStreamer; FFmpeg backend fails to
#                                   initialise NvDec on Nvidia GPUs
#   GST_AUDIOSINK=fakesink       — defense-in-depth: if any GStreamer element
#                                   attempts audio negotiation, route it to a
#                                   null sink (prevents PipeWire SIGSEGV)
#   LIBVA_DRIVER_NAME=nvidia     — load the nvidia VA-API driver for hw decode
#   NVD_BACKEND=direct           — select the direct DRM backend for
#                                   nvidia-vaapi-driver
#   GBM_BACKEND=nvidia-drm       — use Nvidia's GBM implementation for
#                                   Wayland buffer allocation
#   __GLX_VENDOR_LIBRARY_NAME=nvidia — ensure GLX resolves to Nvidia's
#                                       libGLX_nvidia.so, not Mesa

if ! mkdir -p "${SDDM_CONF_DIR}"; then
    _die 2 "Failed to create SDDM config directory: ${SDDM_CONF_DIR}"
fi

# Warn the operator if a theme file already exists (possible conflict)
if [[ -f "${SDDM_CONF_FILE}" ]]; then
    _warn "${SDDM_CONF_FILE} already exists — it will be overwritten."
fi

cat > "${SDDM_CONF_FILE}" << 'EOF'
# /etc/sddm.conf.d/10-theme.conf
# Managed by install.sh — Aurora Greeter
#
# [Theme]   — activates the aurora-greeter theme
# [General] — injects environment variables into the greeter process
#             via SDDM's native GreeterEnvironment key, bypassing
#             PAM sanitization that strips systemd Environment= lines.

[Theme]
Current=aurora-greeter

[General]
GreeterEnvironment=QML_XHR_ALLOW_FILE_READ=1,QML_XHR_ALLOW_FILE_WRITE=1,QT_MEDIA_BACKEND=gstreamer,GST_AUDIOSINK=fakesink,LIBVA_DRIVER_NAME=nvidia,NVD_BACKEND=direct,GBM_BACKEND=nvidia-drm,__GLX_VENDOR_LIBRARY_NAME=nvidia
EOF

_ok "Theme + environment config written: ${SDDM_CONF_FILE}"
_info "Contents:"
sed 's/^/        /' "${SDDM_CONF_FILE}"
_section_done

# ==============================================================================
#  STEP 6 — Clean up legacy systemd drop-in (if present)
# ==============================================================================
_step "6" "Checking for legacy systemd override drop-in"

# Previous versions of this installer wrote environment variables to a systemd
# service drop-in at /etc/systemd/system/sddm.service.d/override.conf.  We
# have since learned that PAM sanitization strips those variables before they
# reach the greeter, so the drop-in is both ineffective and misleading.
#
# If a previous installation left one behind, remove it and reload systemd.

readonly _LEGACY_DROP_IN_DIR="/etc/systemd/system/sddm.service.d"
readonly _LEGACY_DROP_IN_FILE="${_LEGACY_DROP_IN_DIR}/override.conf"

if [[ -f "${_LEGACY_DROP_IN_FILE}" ]]; then
    # Only remove if it's one of ours (contains our managed-by marker)
    if grep -q "Aurora Greeter\|SDDM Aerial Fork\|sddm-aerial" "${_LEGACY_DROP_IN_FILE}" 2>/dev/null; then
        _warn "Found legacy drop-in: ${_LEGACY_DROP_IN_FILE}"
        _info "This file is ineffective (PAM strips its variables) — removing."
        rm -f "${_LEGACY_DROP_IN_FILE}"

        # Remove the directory too if it's now empty
        if [[ -d "${_LEGACY_DROP_IN_DIR}" ]] && [[ -z "$(ls -A "${_LEGACY_DROP_IN_DIR}" 2>/dev/null)" ]]; then
            rmdir "${_LEGACY_DROP_IN_DIR}"
            _info "Removed empty directory: ${_LEGACY_DROP_IN_DIR}"
        fi

        # Reload systemd to un-apply the stale drop-in
        _info "Running: systemctl daemon-reload"
        if systemctl daemon-reload; then
            _ok "systemd reloaded — legacy drop-in purged"
        else
            _warn "systemctl daemon-reload failed — run 'sudo systemctl daemon-reload' manually."
        fi
    else
        _info "Drop-in exists but is not ours — leaving it untouched."
    fi
else
    _ok "No legacy drop-in found — nothing to clean"
fi

_section_done

# ==============================================================================
#  SUMMARY
# ==============================================================================
echo -e ""
echo -e "${_BOLD}${_GREEN}╔══════════════════════════════════════════════════════════════╗${_RESET}"
echo -e "${_BOLD}${_GREEN}║                  Installation complete!                      ║${_RESET}"
echo -e "${_BOLD}${_GREEN}╚══════════════════════════════════════════════════════════════╝${_RESET}"
echo -e ""
echo -e "  ${_BOLD}Theme deployed to:${_RESET}       ${THEME_DEST}"
echo -e "  ${_BOLD}SDDM config:${_RESET}             ${SDDM_CONF_FILE}"
echo -e "  ${_BOLD}Persistent config dir:${_RESET}   ${SDDM_CONFIG_HOME}"
echo -e ""
echo -e "  ${_MAGENTA}${_BOLD}Next steps:${_RESET}"
echo -e "    ${_CYAN}1.${_RESET} Verify the theme renders correctly in a test session:"
echo -e "         ${_DIM}sudo sddm-greeter-qt6 --test-mode --theme ${THEME_DEST}${_RESET}"
echo -e ""
echo -e "    ${_CYAN}2.${_RESET} If all looks good, restart SDDM to go live:"
echo -e "         ${_DIM}sudo systemctl restart sddm${_RESET}"
echo -e ""
echo -e "    ${_CYAN}3.${_RESET} To revert to the previous theme (if a backup was made):"
echo -e "         ${_DIM}sudo rm -rf ${THEME_DEST}${_RESET}"
echo -e "         ${_DIM}sudo mv ${THEME_DEST}.bak_<timestamp> ${THEME_DEST}${_RESET}"
echo -e ""
echo -e "    ${_CYAN}4.${_RESET} Config drawer hotkey inside the greeter:  ${_BOLD}Alt+S${_RESET}"
echo -e ""
