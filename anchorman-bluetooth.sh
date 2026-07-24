#!/bin/bash
# anchorman-bluetooth.sh
# Monitors Thunderbolt dock presence and automatically connects/disconnects
# configured Bluetooth peripherals. Designed to run as a launchd daemon.

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------
CONFIG_FILE="/usr/local/etc/anchorman-bluetooth.conf"
DOCK_NAME=""
POLL_INTERVAL=3
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

is_dock_connected() {
    # Checks the IORegistry for a Thunderbolt switch whose product name
    # contains DOCK_NAME. IOThunderboltSwitchType3 covers TB3/TB4/USB4 docks.
    ioreg -r -c IOThunderboltSwitchType3 -w0 2>/dev/null | grep -q "$DOCK_NAME"
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

if [[ -z "$DOCK_NAME" ]]; then
    log "DOCK_NAME not set in ${CONFIG_FILE} — nothing to monitor. Exiting."
    exit 0
fi

if [[ ${#BLUETOOTH_DEVICES[@]} -eq 0 ]]; then
    log "BLUETOOTH_DEVICES is empty in ${CONFIG_FILE} — nothing to connect. Exiting."
    exit 0
fi

log "Daemon started. Watching for Thunderbolt dock: '${DOCK_NAME}'. Poll interval: ${POLL_INTERVAL}s."

# Perform an initial state check so the daemon is correct on startup
DOCK_WAS_CONNECTED=false
if is_dock_connected; then
    DOCK_WAS_CONNECTED=true
    log "Dock present on startup — connecting Bluetooth devices."
    connect_bluetooth_devices
else
    log "Dock absent on startup — disconnecting Bluetooth devices."
    disconnect_bluetooth_devices
fi

# Polling loop: act only on state transitions, not on every poll
while sleep "$POLL_INTERVAL"; do
    if is_dock_connected; then
        if [[ "$DOCK_WAS_CONNECTED" == "false" ]]; then
            log "Dock connected — connecting Bluetooth devices."
            connect_bluetooth_devices
            DOCK_WAS_CONNECTED=true
        fi
    else
        if [[ "$DOCK_WAS_CONNECTED" == "true" ]]; then
            log "Dock disconnected — disconnecting Bluetooth devices."
            disconnect_bluetooth_devices
            DOCK_WAS_CONNECTED=false
        fi
    fi
done
