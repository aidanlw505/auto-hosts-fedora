#!/bin/bash
# uninstall.sh - Remove auto-hosts-fedora
#
# Usage: sudo bash uninstall.sh
#
# Optionally pass --restore-backup to restore the original /etc/hosts.

set -euo pipefail

SCRIPT_DEST="/usr/local/sbin/auto-hosts-update"
CONFIG_DIR="/etc/auto-hosts"
BACKUP_FILE="/etc/hosts.pre-auto-hosts"
RESTORE_BACKUP=false

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log()  { echo -e "${GREEN}[uninstall]${NC} $*"; }
warn() { echo -e "${YELLOW}[uninstall]${NC} $*"; }
err()  { echo -e "${RED}[uninstall]${NC} $*" >&2; }

for arg in "$@"; do
    [[ "$arg" == "--restore-backup" ]] && RESTORE_BACKUP=true
done

if [[ $EUID -ne 0 ]]; then
    err "Run as root:  sudo bash uninstall.sh"
    exit 1
fi

# ── Stop and disable timer/service ───────────────────────────────────────────

log "Stopping and disabling auto-hosts timer"
systemctl disable --now auto-hosts.timer 2>/dev/null || true
systemctl stop auto-hosts.service 2>/dev/null || true

# ── Remove systemd units ─────────────────────────────────────────────────────

log "Removing systemd units"
rm -f /etc/systemd/system/auto-hosts.service
rm -f /etc/systemd/system/auto-hosts.timer
systemctl daemon-reload

# ── Remove update script ─────────────────────────────────────────────────────

if [[ -f "$SCRIPT_DEST" ]]; then
    log "Removing $SCRIPT_DEST"
    rm -f "$SCRIPT_DEST"
fi

# ── Optionally restore /etc/hosts ────────────────────────────────────────────

if [[ "$RESTORE_BACKUP" == true ]]; then
    if [[ -f "$BACKUP_FILE" ]]; then
        log "Restoring $BACKUP_FILE → /etc/hosts"
        cp "$BACKUP_FILE" /etc/hosts
        restorecon /etc/hosts 2>/dev/null || true
    else
        warn "No backup found at $BACKUP_FILE — /etc/hosts unchanged"
    fi
else
    warn "/etc/hosts has NOT been restored."
    if [[ -f "$BACKUP_FILE" ]]; then
        warn "To restore:  sudo cp $BACKUP_FILE /etc/hosts"
    fi
fi

# ── Leave config directory for user to clean up ──────────────────────────────

if [[ -d "$CONFIG_DIR" ]]; then
    warn "Config directory $CONFIG_DIR was left in place."
    warn "Remove it manually if you no longer need your whitelist/blacklist/myhosts."
fi

log "Uninstall complete."
