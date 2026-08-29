#!/usr/bin/env bash
# One-time setup: installs the auto-mount/auto-share helper + udev rule so that any
# formatted SSD/HDD/USB stick plugged into the Pi is automatically mounted under
# /srv/nas and shared over Samba, with no manual commands needed afterwards.
#
# Usage: sudo ./06-install-automount.sh
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
source lib/common.sh

require_root

HELPER_SRC="$(pwd)/lib/nas-automount.sh"
HELPER_DEST="/usr/local/bin/nas-automount.sh"
RULE_DEST="/etc/udev/rules.d/99-nas-automount.rules"

log "Installing automount helper to $HELPER_DEST..."
install -m 0755 "$HELPER_SRC" "$HELPER_DEST"

log "Installing udev rule..."
cat > "$RULE_DEST" <<'EOF'
# Auto-mount/share any partition plugged in or removed on a USB SSD/HDD/stick.
SUBSYSTEM=="block", KERNEL=="sd[a-z][0-9]*", ACTION=="add", RUN+="/usr/local/bin/nas-automount.sh %k"
SUBSYSTEM=="block", KERNEL=="sd[a-z][0-9]*", ACTION=="remove", RUN+="/usr/local/bin/nas-automount.sh %k"
EOF

log "Reloading udev rules..."
udevadm control --reload-rules
udevadm trigger --action=add --subsystem-match=block

log "Done. Plug in any already-formatted SSD/HDD/USB stick and it will appear"
log "automatically under /srv/nas and as a Samba share (check /var/log/nas-automount.log)."
log "Brand-new/blank drives still need one manual format: ./scripts/02-prepare-disk.sh --format"
