# Anchorman

A macOS launchd daemon that manages your WiFi adapter automatically based on whether you're docked. When you plug into a wired network, WiFi is disabled. When you unplug, WiFi comes back on.

## How it works

A background script watches for network interface events using `route monitor`. When a change is detected, it checks whether any wired ethernet interface has an active link and an IP address. If so, it turns WiFi off. When the wired connection drops, it turns WiFi back on.

## Requirements

- macOS (tested on macOS Sequoia)
- Must be installed as root (launchd system daemon)

## Installation

```bash
sudo ./install.sh
```

This will:

1. Copy the anchorman daemon to `/usr/local/bin/`
2. Install the launchd plist to `/Library/LaunchDaemons/`
3. Start the daemon immediately and on every subsequent boot

## Uninstallation

```bash
sudo ./install.sh --uninstall
```

Log files are left in place and must be removed manually if desired.

## Logs

```bash
tail -f /var/log/anchorman.log
tail -f /var/log/anchorman.error.log
```

## Verifying it works

1. Check the daemon is running:

   ```bash
   sudo launchctl list | grep anchorman
   ```

2. Plug in an ethernet cable — WiFi should turn off within a second.
3. Unplug — WiFi should turn back on.

## Files

| File | Purpose |
|------|---------|
| `anchorman.sh` | The watcher daemon (installed to `/usr/local/bin/`) |
| `com.local.anchorman.plist` | launchd service definition (installed to `/Library/LaunchDaemons/`) |
| `install.sh` | Installer / uninstaller |
