#!/usr/bin/env bash
# install.sh — Install or uninstall the anchorman launchd daemon
#
# Usage:
#   sudo ./install.sh              # install
#   sudo ./install.sh --uninstall  # remove

set -euo pipefail

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------
SCRIPT_NAME="anchorman.sh"
PLIST_NAME="com.local.anchorman.plist"
LABEL="com.local.anchorman"

INSTALL_BIN="/usr/local/bin/${SCRIPT_NAME%.sh}"
INSTALL_PLIST="/Library/LaunchDaemons/${PLIST_NAME}"
LOG_FILE="/var/log/anchorman.log"
ERROR_LOG="/var/log/anchorman.error.log"

# Source files must be in the same directory as this script
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

info()    { echo "${_BOLD}[INFO]${_RESET}  $*"; }
ok()      { echo "${_GREEN}${_BOLD}[ OK ]${_RESET}  $*"; }
warn()    { echo "${_YELLOW}${_BOLD}[WARN]${_RESET}  $*"; }
error()   { echo "${_RED}${_BOLD}[ERROR]${_RESET} $*" >&2; }
die()     { error "$*"; exit 1; }

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

    [[ -f "${REPO_DIR}/${SCRIPT_NAME}" ]] \
        || die "Source script not found: ${REPO_DIR}/${SCRIPT_NAME}"

    [[ -f "${REPO_DIR}/${PLIST_NAME}" ]] \
        || die "Plist not found: ${REPO_DIR}/${PLIST_NAME}"
}

# ---------------------------------------------------------------------------
# Install
# ---------------------------------------------------------------------------
install_daemon() {
    info "Installing anchorman daemon..."

    # 1. Install the watcher script
    cp "${REPO_DIR}/${SCRIPT_NAME}" "${INSTALL_BIN}"
    chmod 755 "${INSTALL_BIN}"

    # 2. Install the launchd plist
    cp "${REPO_DIR}/${PLIST_NAME}" "${INSTALL_PLIST}"
    chown root:wheel "${INSTALL_PLIST}"
    chmod 644 "${INSTALL_PLIST}"

    # 3. Unload any existing instance (ignore "not loaded" errors)
    if launchctl list "${LABEL}" &>/dev/null; then
        info "Daemon already loaded — unloading previous version..."
        launchctl unload "${INSTALL_PLIST}" 2>/dev/null || true
    fi

    # 4. Load the daemon
    launchctl load "${INSTALL_PLIST}"

    # 5. Verify it started
    if ! launchctl list "${LABEL}" &>/dev/null; then
        warn "Daemon loaded but not listed yet — it may start shortly."
    fi

    echo
    echo "${_BOLD}Installation complete.${_RESET}"
    echo
    echo "  Script  : ${INSTALL_BIN}"
    echo "  Plist   : ${INSTALL_PLIST}"
    echo "  Log     : ${LOG_FILE}"
    echo "  Errors  : ${ERROR_LOG}"
    echo
    echo "Tip: plug/unplug in your ethernet cable and watch the log:"
    echo "  tail -f ${LOG_FILE}"
    echo
}

# ---------------------------------------------------------------------------
# Uninstall
# ---------------------------------------------------------------------------
uninstall_daemon() {
    info "Uninstalling anchorman daemon..."

    # 1. Unload the daemon
    if launchctl list "${LABEL}" &>/dev/null; then
        launchctl unload "${INSTALL_PLIST}" 2>/dev/null || true
    else
        warn "Daemon was not loaded — skipping unload."
    fi

    # 2. Remove the plist
    if [[ -f "${INSTALL_PLIST}" ]]; then
        rm -f "${INSTALL_PLIST}"
    else
        warn "Plist not found, skipping: ${INSTALL_PLIST}"
    fi

    # 3. Remove the script
    if [[ -f "${INSTALL_BIN}" ]]; then
        rm -f "${INSTALL_BIN}"
    else
        warn "Script not found, skipping: ${INSTALL_BIN}"
    fi

    echo
    echo "${_BOLD}Uninstall complete.${_RESET}"
    echo "Log files (if any) were left in place:"
    echo "  ${LOG_FILE}"
    echo "  ${ERROR_LOG}"
    echo
}

# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------
ACTION="${1:-}"

preflight "$@"

case "$ACTION" in
    --uninstall) uninstall_daemon ;;
    "")          install_daemon   ;;
    *)           die "Unknown argument: $ACTION\nUsage: sudo $0 [--uninstall]" ;;
esac
