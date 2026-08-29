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
SERVICE_DEST="/etc/systemd/system/nas-automount@.service"

log "Installing automount helper to $HELPER_DEST..."
install -m 0755 "$HELPER_SRC" "$HELPER_DEST"

log "Installing systemd service template (runs outside udev's restricted sandbox, needed for NTFS/exFAT FUSE mounts)..."
cat > "$SERVICE_DEST" <<'EOF'
[Unit]
Description=NAS automount for %i
After=local-fs.target
# Device names (sda1, sdb1, ...) get reused when drives are swapped, which can otherwise
# trip systemd's start-rate-limit for this instance name and block future mounts.
StartLimitIntervalSec=0

[Service]
Type=oneshot
# ntfs-3g/exfat forks a background FUSE daemon after mounting - without KillMode=none,
# systemd reaps that lingering process shortly after this oneshot unit finishes,
# silently unmounting the drive a moment later.
KillMode=none
ExecStart=/usr/local/bin/nas-automount.sh %i
EOF

log "Installing udev rule..."
cat > "$RULE_DEST" <<'EOF'
# Auto-mount/share any partition plugged in or removed on a USB SSD/HDD/stick.
# Tell udisks2 (used by desktop file managers) to ignore these partitions entirely,
# so it doesn't race us to auto-mount them under /media/<user>/... first - NTFS/exFAT
# exclusively lock the device, so whichever mounts first blocks the other.
SUBSYSTEM=="block", KERNEL=="sd[a-z][0-9]*", ENV{UDISKS_IGNORE}="1"
# Hands off to a systemd service instead of mounting inline: systemd-udevd's worker
# processes run in a restricted sandbox that blocks FUSE (ntfs-3g/exfat) mounts.
SUBSYSTEM=="block", KERNEL=="sd[a-z][0-9]*", ACTION=="add", RUN+="/bin/systemctl --no-block start nas-automount@add-%k.service"
SUBSYSTEM=="block", KERNEL=="sd[a-z][0-9]*", ACTION=="remove", RUN+="/bin/systemctl --no-block start nas-automount@remove-%k.service"
EOF

log "Reloading udev rules and systemd..."
udevadm control --reload-rules
systemctl daemon-reload

log "Clearing any stale/stuck automount service instances (oneshot units left 'active' block reused device names from re-mounting)..."
systemctl stop 'nas-automount@*' 2>/dev/null || true
systemctl reset-failed 'nas-automount@*' 2>/dev/null || true
udevadm trigger --action=add --subsystem-match=block

log "Done. Plug in any already-formatted SSD/HDD/USB stick and it will appear"
log "automatically under /srv/nas and as a Samba share (check /var/log/nas-automount.log)."
log "Brand-new/blank drives still need one manual format: ./scripts/02-prepare-disk.sh --format"
