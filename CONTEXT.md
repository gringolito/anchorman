# Anchorman — Domain Context

A glossary of the project's ubiquitous language. Implementation details do not belong here.

## Terms

### Daemon

A single anchorman background service managed by launchd. There are two:
`wifi` (`anchorman-wifi`) and `bluetooth` (`anchorman-bluetooth`).

### Target

The user-facing name for a Daemon on the command line. Valid targets:
`wifi`, `bluetooth`, and `all` (both daemons). `bluetooth` is the official
name — there is no `bt` alias. One or more targets may be given per command;
omitting the target is an error.

### start

Activate a Daemon **for the current session only**. Does not change whether it
comes back after a reboot. Mirrors `systemctl start`.

### stop

Deactivate a Daemon **for the current session only**. A reboot (or a subsequent
`start`) brings it back. Mirrors `systemctl stop`. Because both daemons are
`KeepAlive`, "stop" is a launchd-level operation, not killing the process.

### enable

Make a Daemon **persistently** activate — it survives reboots. Mirrors
`systemctl enable`.

### disable

Make a Daemon **persistently** inactive — it stays off across reboots until
explicitly re-enabled. Mirrors `systemctl disable`.

### --now

A modifier on `enable`/`disable` that also applies the corresponding
session-level action: `enable --now` also `start`s, `disable --now` also
`stop`s. Mirrors `systemctl enable --now`. Invalid with any other verb.

### restart

Bounce a Daemon: if running, terminate and start it again; if stopped, simply
`start` it. Mirrors `systemctl restart`.

### status

Report a Daemon's two axes — current run state (running/stopped) and boot
state (enabled/disabled) — plus a short tail of its log.
