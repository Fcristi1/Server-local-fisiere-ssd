#!/usr/bin/env bash
# Configures Samba to share every drive mounted under /srv/nas and restarts the service.
#
# Usage: sudo ./04-setup-samba.sh
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
source lib/common.sh

require_root

SMB_CONF="/etc/samba/smb.conf"
SHARES_INCLUDE="/etc/samba/nas-shares.conf"
BASE_DIR="/srv/nas"

[[ -d "$BASE_DIR" ]] || die "$BASE_DIR does not exist yet. Run 02-prepare-disk.sh first."

if [[ ! -f "${SMB_CONF}.orig" ]]; then
  log "Backing up original smb.conf to ${SMB_CONF}.orig..."
  cp "$SMB_CONF" "${SMB_CONF}.orig"
fi

if ! grep -q "include = $SHARES_INCLUDE" "$SMB_CONF"; then
  log "Adding include line for $SHARES_INCLUDE to smb.conf..."
  printf '\n[global]\ninclude = %s\n' "$SHARES_INCLUDE" >> "$SMB_CONF"
fi

log "Generating $SHARES_INCLUDE from directories under $BASE_DIR..."
{
  for dir in "$BASE_DIR"/*/; do
    [[ -d "$dir" ]] || continue
    name="$(basename "$dir")"
    cat <<EOF

[$name]
   path = $dir
   valid users = @users
   read only = no
   browsable = yes
   guest ok = no
   create mask = 0664
   directory mask = 2775
EOF
  done
} > "$SHARES_INCLUDE"

log "Testing Samba configuration..."
testparm -s >/dev/null

log "Restarting Samba services..."
systemctl restart smbd nmbd
systemctl enable smbd nmbd

log "Opening firewall for Samba (if ufw is active)..."
ufw allow samba >/dev/null 2>&1 || true

log "Samba shares configured for: $(ls "$BASE_DIR")"
log "Connect from your phone/PC using \\\\$(hostname -I | awk '{print $1}')\\<share-name> or smb://$(hostname -I | awk '{print $1}')/<share-name>"
