# auto-hosts-fedora

Automatically installs and daily-updates [Steven Black's hosts](https://github.com/StevenBlack/hosts) blocklists on Fedora. Uses systemd for scheduling and handles SELinux correctly.

## Features

- Downloads Steven Black's pre-built hosts file (base + optional extension categories)
- Optional blocklist extensions: **fakenews**, **gambling**, **porn**, **social**
- Per-user **whitelist** (un-block specific domains), **blacklist** (add blocks), and **myhosts** (custom host entries)
- Daily auto-update via systemd timer; catches up on boot if the machine was off
- Atomic write to `/etc/hosts` with automatic `restorecon` for SELinux

## Install

```bash
git clone https://github.com/awillingham/auto-hosts-fedora
cd auto-hosts-fedora
sudo bash install.sh
```

The installer:
1. Copies the update script to `/usr/local/sbin/auto-hosts-update`
2. Creates `/etc/auto-hosts/` with starter config files
3. Enables and starts the systemd timer
4. Runs an initial update immediately
5. Backs up your original `/etc/hosts` to `/etc/hosts.pre-auto-hosts`

## Configuration

All config lives in `/etc/auto-hosts/`. After any edit, apply changes immediately with:

```bash
sudo systemctl start auto-hosts.service
```

### `/etc/auto-hosts/config`

```ini
# Enable extension blocklist categories
FAKENEWS=false
GAMBLING=false
PORN=false
SOCIAL=false

# IP that blocked hosts resolve to (0.0.0.0 recommended)
REDIRECT_IP=0.0.0.0
```

### `/etc/auto-hosts/whitelist`

One hostname per line. Removes matching entries from the downloaded blocklist.

```
# Allow these even if Steven Black blocks them
ads.trustedsite.com
```

### `/etc/auto-hosts/blacklist`

One hostname per line. Added to `/etc/hosts` using `REDIRECT_IP`.

```
# Block these in addition to Steven Black's list
tracking.annoying.com
```

### `/etc/auto-hosts/myhosts`

Raw host entries appended verbatim to `/etc/hosts`.

```
192.168.1.100  myserver.local
10.0.0.1       router.home
```

## Usage

| Task | Command |
|------|---------|
| Run update now | `sudo systemctl start auto-hosts.service` |
| View last run logs | `journalctl -u auto-hosts.service` |
| Check timer schedule | `systemctl status auto-hosts.timer` |
| Disable auto-updates | `sudo systemctl disable --now auto-hosts.timer` |
| Restore original hosts | `sudo cp /etc/hosts.pre-auto-hosts /etc/hosts` |

## Uninstall

```bash
sudo bash uninstall.sh                    # remove service, leave /etc/hosts as-is
sudo bash uninstall.sh --restore-backup   # also restore original /etc/hosts
```

Config files in `/etc/auto-hosts/` are left in place so you don't lose your whitelist/blacklist. Remove manually when ready.

## How it works

Steven Black publishes a pre-built hosts file for every extension combination on GitHub. This tool reads your config, constructs the right URL (e.g. `alternates/gambling-porn/hosts`), downloads it, applies your whitelist/blacklist/myhosts, then writes atomically to `/etc/hosts` followed by `restorecon` to restore the `net_conf_t` SELinux label.
