#!/usr/bin/env bash
# One-time bootstrap: wires /etc/samba/nas-shares.conf into smb.conf and (re)generates
# it from whatever is currently under /srv/nas. After this, 02-prepare-disk.sh and the
# automount helper (06-install-automount.sh) keep the shares list up to date on their own.
#
# Usage: sudo ./04-setup-samba.sh
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
source lib/common.sh

require_root

SMB_CONF="/etc/samba/smb.conf"
SHARES_INCLUDE="/etc/samba/nas-shares.conf"
BASE_DIR="/srv/nas"

mkdir -p "$BASE_DIR"

if [[ ! -f "${SMB_CONF}.orig" ]]; then
  log "Backing up original smb.conf to ${SMB_CONF}.orig..."
  cp "$SMB_CONF" "${SMB_CONF}.orig"
fi

if ! grep -q "include = $SHARES_INCLUDE" "$SMB_CONF"; then
  log "Adding include line for $SHARES_INCLUDE to smb.conf..."
  printf '\n[global]\ninclude = %s\n' "$SHARES_INCLUDE" >> "$SMB_CONF"
fi

log "Generating $SHARES_INCLUDE from directories under $BASE_DIR..."
regenerate_samba_shares

log "Testing Samba configuration..."
testparm -s >/dev/null

log "Restarting Samba services..."
systemctl restart smbd nmbd
systemctl enable smbd nmbd

log "Opening firewall for Samba (if ufw is active)..."
ufw allow samba >/dev/null 2>&1 || true

log "Samba shares configured for: $(ls "$BASE_DIR" 2>/dev/null || echo '(none yet)')"
log "Connect from your phone/PC using \\\\$(hostname -I | awk '{print $1}')\\<share-name> or smb://$(hostname -I | awk '{print $1}')/<share-name>"
