#!/bin/bash
# anchorman-bluetooth.sh
# Monitors dock presence and automatically connects/disconnects configured
# Bluetooth peripherals. Handles Thunderbolt docks and plain USB-C docks.
# Designed to run as a launchd daemon.

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------
CONFIG_FILE="/usr/local/etc/anchorman-bluetooth.conf"
POLL_INTERVAL=3

# Docks to watch. DOCK_NAMES and DOCK_MATCHERS are parallel arrays: the
# matcher at index N detects the dock named at index N.
DOCK_NAMES=()
DOCK_MATCHERS=()
BLUETOOTH_DEVICES=()

if [[ -f "$CONFIG_FILE" ]]; then
    # shellcheck source=/dev/null
    source "$CONFIG_FILE"
fi

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [anchorman-bluetooth] $*"
}

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

get_console_user() {
    # Returns the username of whoever is logged in at the console.
    # The daemon runs as root; Bluetooth commands must be issued as the
    # regular user who owns the active GUI session.
    stat -f "%Su" /dev/console 2>/dev/null
}

is_thunderbolt_dock() {
    # Checks the IORegistry for a Thunderbolt switch whose product name
    # contains $1. IOThunderboltSwitchType3 covers TB3/TB4/USB4 docks.
    ioreg -r -c IOThunderboltSwitchType3 -w0 2>/dev/null | grep -q "$1"
}

is_hex4() {
    [[ ${#1} -eq 4 && -z "${1//[[:xdigit:]]/}" ]]
}

is_usb_device() {
    # True when a USB device with vendor/product ID $1:$2 is attached.
    # ioreg prints each node with its properties immediately following it,
    # so comparing the pending ID pair on every new node header keeps a
    # device's vendor and product ID together instead of across nodes.
    local vid pid
    vid=$(printf '%d' "0x$1") || return 1
    pid=$(printf '%d' "0x$2") || return 1

    ioreg -p IOUSB -w0 -l 2>/dev/null | awk -v vid="$vid" -v pid="$pid" '
        /\+-o / {
            if (v == vid && p == pid) found = 1
            v = ""; p = ""
            next
        }
        /"idVendor"/  { v = $NF + 0; next }
        /"idProduct"/ { p = $NF + 0; next }
        END {
            if (v == vid && p == pid) found = 1
            exit found ? 0 : 1
        }
    '
}

dock_matcher_is_valid() {
    case "$1" in
        thunderbolt)
            return 0
            ;;
        usb:*:*)
            local spec vid pid
            spec="${1#usb:}"
            vid="${spec%%:*}"
            pid="${spec##*:}"
            is_hex4 "$vid" && is_hex4 "$pid"
            ;;
        *)
            return 1
            ;;
    esac
}

dock_matcher_matches() {
    case "$2" in
        thunderbolt)
            is_thunderbolt_dock "$1"
            ;;
        usb:*)
            local spec vid pid
            spec="${2#usb:}"
            vid="${spec%%:*}"
            pid="${spec##*:}"
            is_usb_device "$vid" "$pid"
            ;;
        *)
            return 1
            ;;
    esac
}

connected_dock() {
    # Echoes the name of the first attached dock, or fails when none is.
    local i name matcher
    for ((i = 0; i < ${#DOCK_NAMES[@]}; i++)); do
        name="${DOCK_NAMES[$i]}"
        matcher="${DOCK_MATCHERS[$i]}"
        if dock_matcher_matches "$name" "$matcher"; then
            echo "$name"
            return 0
        fi
    done
    return 1
}

# ---------------------------------------------------------------------------
# Actions
# ---------------------------------------------------------------------------

connect_bluetooth_devices() {
    local user
    user=$(get_console_user)
    if [[ -z "$user" || "$user" == "root" ]]; then
        log "No console user found — skipping Bluetooth connect."
        return
    fi
    local mac
    for mac in "${BLUETOOTH_DEVICES[@]}"; do
        log "Connecting Bluetooth device: $mac"
        su -l "$user" -c "blueutil --connect '$mac'" &
    done
}

disconnect_bluetooth_devices() {
    local user
    user=$(get_console_user)
    if [[ -z "$user" || "$user" == "root" ]]; then
        log "No console user found — skipping Bluetooth disconnect."
        return
    fi
    local mac
    for mac in "${BLUETOOTH_DEVICES[@]}"; do
        log "Disconnecting Bluetooth device: $mac"
        su -l "$user" -c "blueutil --disconnect '$mac'" &
    done
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

if [[ ${#DOCK_NAMES[@]} -eq 0 ]]; then
    log "DOCK_NAMES is empty in ${CONFIG_FILE} — nothing to monitor. Exiting."
    exit 0
fi

if [[ ${#DOCK_NAMES[@]} -ne ${#DOCK_MATCHERS[@]} ]]; then
    log "DOCK_NAMES and DOCK_MATCHERS must have the same number of entries in ${CONFIG_FILE}. Exiting."
    exit 1
fi

for ((i = 0; i < ${#DOCK_NAMES[@]}; i++)); do
    if ! dock_matcher_is_valid "${DOCK_MATCHERS[$i]}"; then
        log "Invalid matcher '${DOCK_MATCHERS[$i]}' for dock '${DOCK_NAMES[$i]}' in ${CONFIG_FILE}. Exiting."
        exit 1
    fi
done

if [[ ${#BLUETOOTH_DEVICES[@]} -eq 0 ]]; then
    log "BLUETOOTH_DEVICES is empty in ${CONFIG_FILE} — nothing to connect. Exiting."
    exit 0
fi

log "Daemon started. Watching for ${#DOCK_NAMES[@]} dock(s): ${DOCK_NAMES[*]}. Poll interval: ${POLL_INTERVAL}s."

# Perform an initial state check so the daemon is correct on startup
DOCK_WAS_CONNECTED=false
DOCK_NAME=""
if DOCK_NAME=$(connected_dock); then
    DOCK_WAS_CONNECTED=true
    log "Dock present on startup ('$DOCK_NAME') — connecting Bluetooth devices."
    connect_bluetooth_devices
else
    DOCK_NAME=""
    log "Dock absent on startup — disconnecting Bluetooth devices."
    disconnect_bluetooth_devices
fi

# Polling loop: act only on state transitions, not on every poll
while sleep "$POLL_INTERVAL"; do
    if DOCK_NAME=$(connected_dock); then
        if [[ "$DOCK_WAS_CONNECTED" == "false" ]]; then
            log "Dock connected ('$DOCK_NAME') — connecting Bluetooth devices."
            connect_bluetooth_devices
            DOCK_WAS_CONNECTED=true
        fi
    elif [[ "$DOCK_WAS_CONNECTED" == "true" ]]; then
        log "Dock disconnected — disconnecting Bluetooth devices."
        disconnect_bluetooth_devices
        DOCK_WAS_CONNECTED=false
    fi
done
