#!/usr/bin/env bash
# One-time bootstrap (safe to re-run): replaces /etc/samba/smb.conf with a clean, minimal
# config containing ONLY the NAS drive shares from /etc/samba/nas-shares.conf - so no
# leftover/custom shares (home directories, desktop file-sharing, printers, etc.) can ever
# expose anything beyond what's currently mounted under /srv/nas.
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

log "Writing a clean smb.conf (drops any pre-existing custom/home/printer shares)..."
cat > "$SMB_CONF" <<EOF
[global]
   workgroup = WORKGROUP
   server string = Raspberry Pi NAS
   security = user
   map to guest = never
   load printers = no
   printing = bsd
   printcap name = /dev/null
   disable spoolss = yes
   usershare max shares = 0

   # Performance tuning for USB SSD/HDD transfers over LAN
   server multi channel support = yes
   socket options = TCP_NODELAY IPTOS_LOWDELAY SO_RCVBUF=131072 SO_SNDBUF=131072
   use sendfile = yes
   min receivefile size = 16384
   strict allocate = yes
   read raw = yes
   write raw = yes

   include = $SHARES_INCLUDE
EOF

# "usershares" (e.g. from the desktop file manager's Sharing tab) can expose folders
# like the whole filesystem or /home independently of smb.conf - wipe any of those out.
if [[ -d /var/lib/samba/usershares ]]; then
  EXISTING_USERSHARES="$(find /var/lib/samba/usershares -mindepth 1 -maxdepth 1 2>/dev/null)"
  if [[ -n "$EXISTING_USERSHARES" ]]; then
    warn "Removing existing Samba usershares (desktop file-sharing leftovers): $EXISTING_USERSHARES"
    rm -f /var/lib/samba/usershares/*
  fi
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
