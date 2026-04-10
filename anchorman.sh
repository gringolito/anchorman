#!/bin/bash
# anchorman.sh
# Monitors ethernet state and automatically enables/disables WiFi.
# Designed to run as a launchd daemon.

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [anchorman] $*"
}

# ---------------------------------------------------------------------------
# Interface discovery
# ---------------------------------------------------------------------------

get_wifi_device() {
    # Returns the device name (e.g. en0) for the Wi-Fi adapter.
    # networksetup -setairportpower / -getairportpower accept the device name
    # reliably; passing the Hardware Port label ("Wi-Fi") causes a warning on
    # some macOS versions because it is interpreted as a device name.
    networksetup -listallhardwareports | awk '
        /Hardware Port:.*([Ww]i[-]?[Ff]i|AirPort)/ { found=1 }
        found && /Device:/ { print $2; exit }
    '
}

get_ethernet_interfaces() {
    # Returns device names (en0, en1, …) for all wired ports.
    # Strategy: exclude Wi-Fi / AirPort rows instead of hard-coding wired
    # port types, so the script works on any machine regardless of how Apple
    # names Thunderbolt Ethernet adapters, USB-C hubs, etc.
    networksetup -listallhardwareports | awk '
        /Hardware Port:/ {
            is_wifi = /[Ww]i[-]?[Ff]i|AirPort/
            port = 1
        }
        port && !is_wifi && /Device: en[0-9]+/ {
            print $2
            port = 0
        }
    '
}

# ---------------------------------------------------------------------------
# State checks
# ---------------------------------------------------------------------------

is_ethernet_active() {
    local ifaces
    ifaces=$(get_ethernet_interfaces)

    if [[ -z "$ifaces" ]]; then
        return 1  # no wired interfaces found
    fi

    for iface in $ifaces; do
        local status ip
        status=$(ifconfig "$iface" 2>/dev/null | grep "status: active")
        ip=$(ipconfig getifaddr "$iface" 2>/dev/null)

        if [[ -n "$status" && -n "$ip" ]]; then
            log "Ethernet active on $iface (IP: $ip)"
            return 0
        fi
    done

    return 1
}

is_wifi_on() {
    local state
    state=$(networksetup -getairportpower "$WIFI_DEVICE" 2>/dev/null | awk '{print $NF}')
    [[ "$state" == "On" ]]
}

# ---------------------------------------------------------------------------
# Actions
# ---------------------------------------------------------------------------

disable_wifi() {
    if is_wifi_on; then
        log "Ethernet detected — disabling WiFi ($WIFI_DEVICE)"
        networksetup -setairportpower "$WIFI_DEVICE" off
    fi
}

enable_wifi() {
    if ! is_wifi_on; then
        log "Ethernet gone — enabling WiFi ($WIFI_DEVICE)"
        networksetup -setairportpower "$WIFI_DEVICE" on
    fi
}

check_and_toggle() {
    if is_ethernet_active; then
        disable_wifi
    else
        enable_wifi
    fi
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

WIFI_DEVICE=$(get_wifi_device)

if [[ -z "$WIFI_DEVICE" ]]; then
    log "No Wi-Fi adapter found via networksetup — nothing to manage. Exiting."
    exit 0
fi

log "Daemon started. Wi-Fi device: '$WIFI_DEVICE'. Monitoring via route events."

# Initial check on startup
check_and_toggle

# Event-driven loop: filter route monitor output to only the three event types
# that signal a physical connection change:
#   RTM_IFINFO  — interface link status changed (cable plugged/unplugged)
#   RTM_NEWADDR — an IP address was assigned to an interface
#   RTM_DELADDR — an IP address was removed from an interface
#
# All other events (ARP updates, RTM_ADD/DELETE for host routes, multicast
# routes, etc.) are ignored, keeping CPU usage at zero between real changes.
route monitor 2>/dev/null | while read -r line; do
    case "$line" in
        RTM_IFINFO:*|RTM_NEWADDR:*|RTM_DELADDR:*)
            check_and_toggle
            ;;
    esac
done
