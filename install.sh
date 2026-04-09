#!/bin/bash
# install.sh - Set up auto-hosts-fedora
#
# Usage: sudo bash install.sh
#
# What this does:
#   - Installs update-hosts.py to /usr/local/sbin/auto-hosts-update
#   - Creates /etc/auto-hosts/ with config, whitelist, blacklist, myhosts
#   - Installs and enables the systemd timer (runs daily)
#   - Runs an initial update immediately

set -euo pipefail

SCRIPT_NAME="auto-hosts"
SCRIPT_SRC="update-hosts.py"
SCRIPT_DEST="/usr/local/sbin/auto-hosts-update"
CONFIG_DIR="/etc/auto-hosts"
BACKUP_FILE="/etc/hosts.pre-auto-hosts"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log()  { echo -e "${GREEN}[install]${NC} $*"; }
warn() { echo -e "${YELLOW}[install]${NC} $*"; }
err()  { echo -e "${RED}[install]${NC} $*" >&2; }

# ── Preflight ────────────────────────────────────────────────────────────────

if [[ $EUID -ne 0 ]]; then
    err "Run as root:  sudo bash install.sh"
    exit 1
fi

if [[ ! -f "$SCRIPT_SRC" ]]; then
    err "Cannot find $SCRIPT_SRC — run this script from the repo directory."
    exit 1
fi

if ! command -v python3 &>/dev/null; then
    err "python3 is required but not installed."
    exit 1
fi

# ── Install update script ────────────────────────────────────────────────────

log "Installing update script → $SCRIPT_DEST"
install -m 755 "$SCRIPT_SRC" "$SCRIPT_DEST"

# ── Install systemd units ────────────────────────────────────────────────────

log "Installing systemd units"
install -m 644 auto-hosts.service /etc/systemd/system/
install -m 644 auto-hosts.timer   /etc/systemd/system/

# ── Create config directory and files ───────────────────────────────────────

mkdir -p "$CONFIG_DIR"
chmod 755 "$CONFIG_DIR"

# Config — do not overwrite if the user has already customised it
if [[ ! -f "$CONFIG_DIR/config" ]]; then
    log "Creating $CONFIG_DIR/config"
    cat > "$CONFIG_DIR/config" << 'EOF'
# auto-hosts configuration
# After editing, trigger an immediate update with:
#   sudo systemctl start auto-hosts.service

# ── Steven Black extension lists ─────────────────────────────────────────────
# Set any of these to true to include that blocklist category.
#
# fakenews  - fake news sites
# gambling  - gambling sites
# porn      - adult content
# social    - social media platforms
#
FAKENEWS=false
GAMBLING=false
PORN=false
SOCIAL=false

# ── Redirect IP ──────────────────────────────────────────────────────────────
# IP that blocked hostnames resolve to.
# 0.0.0.0 is recommended: connections fail immediately (no loopback overhead).
# Use 127.0.0.1 if you want a local web server to serve a block page.
REDIRECT_IP=0.0.0.0
EOF
else
    warn "$CONFIG_DIR/config already exists — skipping (your settings are preserved)"
fi

if [[ ! -f "$CONFIG_DIR/whitelist" ]]; then
    log "Creating $CONFIG_DIR/whitelist"
    cat > "$CONFIG_DIR/whitelist" << 'EOF'
# whitelist - Domains to ALLOW even if blocked by Steven Black's lists
#
# Add one hostname per line. Lines starting with # are ignored.
# After editing, run:  sudo systemctl start auto-hosts.service
#
# Example:
#   ads.example.com
#   tracker.trustedsite.com
EOF
else
    warn "$CONFIG_DIR/whitelist already exists — skipping"
fi

if [[ ! -f "$CONFIG_DIR/blacklist" ]]; then
    log "Creating $CONFIG_DIR/blacklist"
    cat > "$CONFIG_DIR/blacklist" << 'EOF'
# blacklist - Additional domains to BLOCK
#
# Add one hostname per line. Lines starting with # are ignored.
# These entries use the REDIRECT_IP set in config.
# After editing, run:  sudo systemctl start auto-hosts.service
#
# Example:
#   tracking.example.com
#   ads.annoyingsite.net
EOF
else
    warn "$CONFIG_DIR/blacklist already exists — skipping"
fi

if [[ ! -f "$CONFIG_DIR/myhosts" ]]; then
    log "Creating $CONFIG_DIR/myhosts"
    cat > "$CONFIG_DIR/myhosts" << 'EOF'
# myhosts - Custom host entries
#
# These are appended verbatim to the end of /etc/hosts.
# Use standard hosts file format:  <IP>  <hostname>
# After editing, run:  sudo systemctl start auto-hosts.service
#
# Example:
#   192.168.1.100  myserver.local
#   10.0.0.1       router.home
EOF
else
    warn "$CONFIG_DIR/myhosts already exists — skipping"
fi

chmod 644 "$CONFIG_DIR/config" "$CONFIG_DIR/whitelist" \
          "$CONFIG_DIR/blacklist" "$CONFIG_DIR/myhosts"

# ── Backup existing /etc/hosts ───────────────────────────────────────────────

if [[ ! -f "$BACKUP_FILE" ]]; then
    log "Backing up current /etc/hosts → $BACKUP_FILE"
    cp /etc/hosts "$BACKUP_FILE"
else
    warn "Backup already exists at $BACKUP_FILE — not overwriting"
fi

# ── Enable systemd timer ─────────────────────────────────────────────────────

log "Reloading systemd and enabling timer"
systemctl daemon-reload
systemctl enable --now auto-hosts.timer

# ── Initial update ───────────────────────────────────────────────────────────

log "Running initial hosts update..."
systemctl start auto-hosts.service

echo ""
log "Installation complete!"
echo ""
echo "  Config:    $CONFIG_DIR/config"
echo "  Whitelist: $CONFIG_DIR/whitelist"
echo "  Blacklist: $CONFIG_DIR/blacklist"
echo "  Myhosts:   $CONFIG_DIR/myhosts"
echo ""
echo "  Update now:       sudo systemctl start auto-hosts.service"
echo "  View logs:        journalctl -u auto-hosts.service"
echo "  Timer status:     systemctl status auto-hosts.timer"
echo "  Restore backup:   sudo cp $BACKUP_FILE /etc/hosts"
