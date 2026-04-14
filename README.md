# Anchorman

You have a wired workbench: a Thunderbolt dock, ethernet, display, a pair of speakers and a Bluetooth keyboard and mouse. Two Macs live on that desk — one for work, one for personal use. Switching between them should be as simple as moving a single cable.

Without Anchorman, that means manually connecting Bluetooth devices, waiting for them to pair, and disabling WiFi so you're actually on the fast wired network. Every. Single. Time.

**Anchorman automates all of that.** Plug the Thunderbolt cable into a Mac and within seconds:

- Your Bluetooth keyboard and mouse connect to it automatically
- WiFi turns off because you're already on ethernet

Unplug and hand the cable to the other Mac — it takes over just as seamlessly. No menus, no pairing screens, no forgotten WiFi toggle.

---

A pair of macOS launchd daemons that manage your peripherals automatically when you dock and undock.

| Daemon                | What it does                                     |
|-----------------------|--------------------------------------------------|
| `anchorman-wifi`      | Disables WiFi when docked to ethernet            |
| `anchorman-bluetooth` | Connects Bluetooth peripherals when dock present |

## Requirements

- macOS (tested on macOS Sequoia)
- Must be installed as root (launchd system daemon)
- [`blueutil`](https://github.com/toy/blueutil) for the Bluetooth daemon: `brew install blueutil`

## Installation

```bash
sudo ./install.sh
```

This installs both daemons. To install only one:

```bash
sudo ./install.sh --wifi
sudo ./install.sh --bluetooth
```

## Uninstallation

```bash
sudo ./install.sh --uninstall
```

Log files and the Bluetooth config file are left in place and must be removed manually if desired.

## WiFi Manager (anchorman-wifi)

Watches for network interface events using `route monitor`. When a change is detected, it checks whether any wired ethernet interface has an active link and an assigned IP. If so, it turns WiFi off; when the wired connection drops, WiFi comes back on.

**Logs:**

```bash
tail -f /var/log/anchorman-wifi.log
tail -f /var/log/anchorman-wifi.error.log
```

**Verify it works:** plug in an ethernet cable — WiFi should turn off within a second. Unplug — WiFi comes back.

## Bluetooth Manager (anchorman-bluetooth)

Polls the IORegistry every few seconds for a specific Thunderbolt dock. When the dock appears, it connects the configured Bluetooth devices. When the dock is removed, it disconnects them.

This means when you move the Thunderbolt cable from Mac A to Mac B:

1. Mac A detects dock removal → disconnects your keyboard and mouse
2. Mac B detects dock arrival → connects your keyboard and mouse

### Setup

#### 1. Find your dock name

```bash
system_profiler SPThunderboltDataType
```

Look for `device_name_key`. Use any unique substring of the name as your `DOCK_NAME`.

#### 2. Find your Bluetooth device MAC addresses

```bash
blueutil --paired
```

#### 3. Edit the config file

```bash
sudo nano /usr/local/etc/anchorman-bluetooth.conf
```

```bash
DOCK_NAME="Express Dock"   # substring of your dock's product name
BLUETOOTH_DEVICES=("aa:bb:cc:dd:ee:ff" "11:22:33:44:55:66")
```

#### 4. Reload the daemon

```bash
sudo launchctl unload /Library/LaunchDaemons/com.gringolito.anchorman-bluetooth.plist
sudo launchctl load  /Library/LaunchDaemons/com.gringolito.anchorman-bluetooth.plist
```

**Logs:**

```bash
tail -f /var/log/anchorman-bluetooth.log
tail -f /var/log/anchorman-bluetooth.error.log
```

## Verifying the daemons are running

```bash
sudo launchctl list | grep anchorman
```

## Files

| File | Purpose |
|------|---------|
| `anchorman-wifi.sh` | WiFi daemon (installed to `/usr/local/bin/`) |
| `anchorman-bluetooth.sh` | Bluetooth daemon (installed to `/usr/local/bin/`) |
| `com.gringolito.anchorman-wifi.plist` | launchd service definition for WiFi daemon |
| `com.gringolito.anchorman-bluetooth.plist` | launchd service definition for Bluetooth daemon |
| `install.sh` | Installer / uninstaller |
