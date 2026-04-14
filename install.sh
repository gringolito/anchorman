#!/usr/bin/env bash
# install.sh — Install or uninstall the anchorman launchd daemons
#
# Usage:
#   sudo ./install.sh                    # install both daemons
#   sudo ./install.sh --wifi             # install WiFi daemon only
#   sudo ./install.sh --bluetooth        # install Bluetooth daemon only
#   sudo ./install.sh --uninstall        # uninstall both daemons
#   sudo ./install.sh --uninstall --wifi       # uninstall WiFi daemon only
#   sudo ./install.sh --uninstall --bluetooth  # uninstall Bluetooth daemon only

set -euo pipefail

# ---------------------------------------------------------------------------
# Usage / help
# ---------------------------------------------------------------------------
usage() {
    cat <<EOF
Usage: sudo ./install.sh [--wifi | --bluetooth] [--uninstall]

Install or uninstall the anchorman launchd daemons.
Installs both daemons when run without options.

Options:
  --wifi         Target only the WiFi daemon (disables WiFi when ethernet is active)
  --bluetooth    Target only the Bluetooth daemon (connects BT devices when dock is present)
  --uninstall    Remove instead of install the targeted daemon(s)
  -h, --help     Show this help message and exit
EOF
}

# ---------------------------------------------------------------------------
# Paths — WiFi daemon
# ---------------------------------------------------------------------------
WIFI_SCRIPT_NAME="anchorman-wifi.sh"
WIFI_PLIST_NAME="com.gringolito.anchorman-wifi.plist"
WIFI_LABEL="com.gringolito.anchorman-wifi"
WIFI_INSTALL_BIN="/usr/local/bin/anchorman-wifi"
WIFI_INSTALL_PLIST="/Library/LaunchDaemons/${WIFI_PLIST_NAME}"
WIFI_LOG="/var/log/anchorman-wifi.log"
WIFI_ERROR_LOG="/var/log/anchorman-wifi.error.log"

# ---------------------------------------------------------------------------
# Paths — Bluetooth daemon
# ---------------------------------------------------------------------------
BT_SCRIPT_NAME="anchorman-bluetooth.sh"
BT_PLIST_NAME="com.gringolito.anchorman-bluetooth.plist"
BT_LABEL="com.gringolito.anchorman-bluetooth"
BT_INSTALL_BIN="/usr/local/bin/anchorman-bluetooth"
BT_INSTALL_PLIST="/Library/LaunchDaemons/${BT_PLIST_NAME}"
BT_CONF="/usr/local/etc/anchorman-bluetooth.conf"
BT_LOG="/var/log/anchorman-bluetooth.log"
BT_ERROR_LOG="/var/log/anchorman-bluetooth.error.log"

# Source files are in the same directory as this script
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ---------------------------------------------------------------------------
# Colour helpers
# ---------------------------------------------------------------------------
if [[ -t 1 ]] && command -v tput &>/dev/null; then
    _BOLD=$(tput bold)
    _GREEN=$(tput setaf 2)
    _YELLOW=$(tput setaf 3)
    _RED=$(tput setaf 1)
    _RESET=$(tput sgr0)
else
    _BOLD="" _GREEN="" _YELLOW="" _RED="" _RESET=""
fi

info()  { echo "${_BOLD}[INFO]${_RESET}  $*"; }
ok()    { echo "${_GREEN}${_BOLD}[ OK ]${_RESET}  $*"; }
warn()  { echo "${_YELLOW}${_BOLD}[WARN]${_RESET}  $*"; }
error() { echo "${_RED}${_BOLD}[ERROR]${_RESET} $*" >&2; }
die()   { error "$*"; exit 1; }

# ---------------------------------------------------------------------------
# Preflight checks
# ---------------------------------------------------------------------------
preflight() {
    [[ "$(uname)" == "Darwin" ]] \
        || die "This script is macOS-only."

    [[ $EUID -eq 0 ]] \
        || die "Run with sudo: sudo $0 $*"

    command -v networksetup &>/dev/null \
        || die "networksetup not found — is this macOS?"
}

preflight_wifi() {
    [[ -f "${REPO_DIR}/${WIFI_SCRIPT_NAME}" ]] \
        || die "Source script not found: ${REPO_DIR}/${WIFI_SCRIPT_NAME}"
    [[ -f "${REPO_DIR}/${WIFI_PLIST_NAME}" ]] \
        || die "Plist not found: ${REPO_DIR}/${WIFI_PLIST_NAME}"
}

preflight_bluetooth() {
    [[ -f "${REPO_DIR}/${BT_SCRIPT_NAME}" ]] \
        || die "Source script not found: ${REPO_DIR}/${BT_SCRIPT_NAME}"
    [[ -f "${REPO_DIR}/${BT_PLIST_NAME}" ]] \
        || die "Plist not found: ${REPO_DIR}/${BT_PLIST_NAME}"
    if ! command -v blueutil &>/dev/null; then
        warn "blueutil not found — Bluetooth management will not work until it is installed."
        warn "Install it with: brew install blueutil"
    fi
}

# ---------------------------------------------------------------------------
# Install WiFi daemon
# ---------------------------------------------------------------------------
install_wifi() {
    info "Installing anchorman-wifi daemon..."

    cp "${REPO_DIR}/${WIFI_SCRIPT_NAME}" "${WIFI_INSTALL_BIN}"
    chmod 755 "${WIFI_INSTALL_BIN}"

    cp "${REPO_DIR}/${WIFI_PLIST_NAME}" "${WIFI_INSTALL_PLIST}"
    chown root:wheel "${WIFI_INSTALL_PLIST}"
    chmod 644 "${WIFI_INSTALL_PLIST}"

    if launchctl list "${WIFI_LABEL}" &>/dev/null; then
        launchctl unload "${WIFI_INSTALL_PLIST}" 2>/dev/null || true
    fi
    launchctl load "${WIFI_INSTALL_PLIST}"

    if ! launchctl list "${WIFI_LABEL}" &>/dev/null; then
        warn "Daemon loaded but not listed yet — it may start shortly."
    fi

    ok "anchorman-wifi installed."
    echo "  Script : ${WIFI_INSTALL_BIN}"
    echo "  Plist  : ${WIFI_INSTALL_PLIST}"
    echo "  Log    : ${WIFI_LOG}"
    echo "  Errors : ${WIFI_ERROR_LOG}"
}

# ---------------------------------------------------------------------------
# Install Bluetooth daemon
# ---------------------------------------------------------------------------
install_bluetooth() {
    info "Installing anchorman-bluetooth daemon..."

    cp "${REPO_DIR}/${BT_SCRIPT_NAME}" "${BT_INSTALL_BIN}"
    chmod 755 "${BT_INSTALL_BIN}"

    cp "${REPO_DIR}/${BT_PLIST_NAME}" "${BT_INSTALL_PLIST}"
    chown root:wheel "${BT_INSTALL_PLIST}"
    chmod 644 "${BT_INSTALL_PLIST}"

    # Create sample config if one doesn't exist yet
    if [[ ! -f "${BT_CONF}" ]]; then
        mkdir -p "$(dirname "${BT_CONF}")"
        cat > "${BT_CONF}" <<'EOF'
# anchorman-bluetooth.conf
# Configuration for the anchorman-bluetooth dock Bluetooth manager.

# Name of your Thunderbolt dock as reported by macOS.
# Use any unique substring of the dock's product name.
# To find your dock name, run:
#   system_profiler SPThunderboltDataType
DOCK_NAME=""

# How often (in seconds) to check for dock presence (default: 3)
POLL_INTERVAL=3

# Bluetooth devices to connect when the dock is detected.
# Find paired device MAC addresses with: blueutil --paired
# Example:
#   BLUETOOTH_DEVICES=("aa-bb-cc-dd-ee-ff" "11-22-33-44-55-66")
BLUETOOTH_DEVICES=()
EOF
        warn "Edit ${BT_CONF} to set your DOCK_NAME and BLUETOOTH_DEVICES before the daemon will do anything."
    fi

    if launchctl list "${BT_LABEL}" &>/dev/null; then
        launchctl unload "${BT_INSTALL_PLIST}" 2>/dev/null || true
    fi
    launchctl load "${BT_INSTALL_PLIST}"

    if ! launchctl list "${BT_LABEL}" &>/dev/null; then
        warn "Daemon loaded but not listed yet — it may start shortly."
    fi

    ok "anchorman-bluetooth installed."
    echo "  Script : ${BT_INSTALL_BIN}"
    echo "  Plist  : ${BT_INSTALL_PLIST}"
    echo "  Config : ${BT_CONF}"
    echo "  Log    : ${BT_LOG}"
    echo "  Errors : ${BT_ERROR_LOG}"
}

# ---------------------------------------------------------------------------
# Uninstall WiFi daemon
# ---------------------------------------------------------------------------
uninstall_wifi() {
    info "Uninstalling anchorman-wifi daemon..."

    if launchctl list "${WIFI_LABEL}" &>/dev/null; then
        launchctl unload "${WIFI_INSTALL_PLIST}" 2>/dev/null || true
    else
        warn "WiFi daemon was not loaded — skipping unload."
    fi

    [[ -f "${WIFI_INSTALL_PLIST}" ]] && rm -f "${WIFI_INSTALL_PLIST}" \
        || warn "Plist not found, skipping: ${WIFI_INSTALL_PLIST}"
    [[ -f "${WIFI_INSTALL_BIN}" ]] && rm -f "${WIFI_INSTALL_BIN}" \
        || warn "Script not found, skipping: ${WIFI_INSTALL_BIN}"

    ok "anchorman-wifi uninstalled."
    echo "  Log files left in place: ${WIFI_LOG}, ${WIFI_ERROR_LOG}"
}

# ---------------------------------------------------------------------------
# Uninstall Bluetooth daemon
# ---------------------------------------------------------------------------
uninstall_bluetooth() {
    info "Uninstalling anchorman-bluetooth daemon..."

    if launchctl list "${BT_LABEL}" &>/dev/null; then
        launchctl unload "${BT_INSTALL_PLIST}" 2>/dev/null || true
    else
        warn "Bluetooth daemon was not loaded — skipping unload."
    fi

    [[ -f "${BT_INSTALL_PLIST}" ]] && rm -f "${BT_INSTALL_PLIST}" \
        || warn "Plist not found, skipping: ${BT_INSTALL_PLIST}"
    [[ -f "${BT_INSTALL_BIN}" ]] && rm -f "${BT_INSTALL_BIN}" \
        || warn "Script not found, skipping: ${BT_INSTALL_BIN}"

    ok "anchorman-bluetooth uninstalled."
    echo "  Config left in place: ${BT_CONF}"
    echo "  Log files left in place: ${BT_LOG}, ${BT_ERROR_LOG}"
}

# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------
UNINSTALL=false
COMPONENT=""  # "wifi", "bluetooth", or "" (both)

for arg in "$@"; do
    case "$arg" in
        --uninstall)    UNINSTALL=true ;;
        --wifi)         COMPONENT="wifi" ;;
        --bluetooth)    COMPONENT="bluetooth" ;;
        -h|--help)      usage; exit 0 ;;
        *) error "Unknown argument: $arg"; echo >&2; usage >&2; exit 1 ;;
    esac
done

preflight "$@"

if [[ "$UNINSTALL" == "true" ]]; then
    case "$COMPONENT" in
        wifi)      uninstall_wifi ;;
        bluetooth) uninstall_bluetooth ;;
        *)         uninstall_wifi; uninstall_bluetooth ;;
    esac
else
    case "$COMPONENT" in
        wifi)
            preflight_wifi
            install_wifi
            echo
            echo "Tip: plug/unplug your ethernet cable and watch:"
            echo "  tail -f ${WIFI_LOG}"
            ;;
        bluetooth)
            preflight_bluetooth
            install_bluetooth
            echo
            echo "Tip: plug/unplug your Thunderbolt dock and watch:"
            echo "  tail -f ${BT_LOG}"
            ;;
        *)
            preflight_wifi
            preflight_bluetooth
            echo
            install_wifi
            echo
            install_bluetooth
            echo
            echo "Tip: plug/unplug your Thunderbolt dock and watch both logs:"
            echo "  tail -f ${WIFI_LOG} ${BT_LOG}"
            ;;
    esac
fi
echo
