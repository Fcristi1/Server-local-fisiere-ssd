#!/usr/bin/env bash
# Formats (optional) and mounts a USB drive, then adds a persistent /etc/fstab entry using its UUID.
#
# Usage:
#   sudo ./02-prepare-disk.sh --list
#   sudo ./02-prepare-disk.sh --device /dev/sda --label data1 [--format]
#
# --format wipes the whole disk and creates a single ext4 partition. Omit it to reuse an
# already-formatted disk/partition (pass the partition, e.g. /dev/sda1, in that case).
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
source lib/common.sh

require_root

usage() { grep '^#' "$0" | sed 's/^# \{0,1\}//' | head -n 9; exit 1; }

DEVICE=""
LABEL=""
DO_FORMAT=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --list) lsblk -o NAME,SIZE,FSTYPE,LABEL,UUID,MOUNTPOINT,MODEL; exit 0 ;;
    --device) DEVICE="$2"; shift 2 ;;
    --label) LABEL="$2"; shift 2 ;;
    --format) DO_FORMAT=1; shift ;;
    -h|--help) usage ;;
    *) die "Unknown argument: $1" ;;
  esac
done

[[ -n "$DEVICE" ]] || die "Missing --device. Run with --list to see available disks."
[[ -b "$DEVICE" ]] || die "$DEVICE is not a block device."
[[ -n "$LABEL" ]] || die "Missing --label (used as the mount point name under /srv/nas)."

MOUNT_POINT="/srv/nas/$LABEL"
PARTITION="$DEVICE"

if [[ $DO_FORMAT -eq 1 ]]; then
  warn "This will ERASE ALL DATA on $DEVICE."
  lsblk "$DEVICE"
  confirm "Type y to confirm you selected the correct disk and want to wipe it" || die "Aborted."

  log "Creating a new GPT partition table and single partition on $DEVICE..."
  parted -s "$DEVICE" mklabel gpt
  parted -s "$DEVICE" mkpart primary ext4 0% 100%
  sleep 2
  partprobe "$DEVICE"
  sleep 2

  PARTITION="${DEVICE}1"
  [[ -b "$PARTITION" ]] || PARTITION="${DEVICE}p1"
  [[ -b "$PARTITION" ]] || die "Could not find the new partition (expected ${DEVICE}1)."

  log "Formatting $PARTITION as ext4 with label $LABEL..."
  mkfs.ext4 -F -L "$LABEL" "$PARTITION"
fi

UUID="$(blkid -s UUID -o value "$PARTITION")"
[[ -n "$UUID" ]] || die "Could not read UUID for $PARTITION. Is it formatted?"

FSTYPE="$(blkid -s TYPE -o value "$PARTITION")"
[[ -n "$FSTYPE" ]] || die "Could not detect a filesystem on $PARTITION. Use --format or format it first."

if ! getent group users >/dev/null; then
  log "Creating shared 'users' group..."
  groupadd users
fi
GID="$(getent group users | cut -d: -f3)"

log "Creating mount point $MOUNT_POINT..."
mkdir -p "$MOUNT_POINT"

# NTFS/exFAT have no Unix permission bits, so grant write access to the whole
# 'users' group via mount options instead of chown/chmod (which only work on ext4).
case "$FSTYPE" in
  ext4|ext3|ext2) MOUNT_OPTS="defaults,nofail,noatime" ;;
  ntfs)           MOUNT_OPTS="defaults,nofail,noatime,uid=0,gid=$GID,umask=002" ;;
  exfat)          MOUNT_OPTS="defaults,nofail,noatime,uid=0,gid=$GID,umask=002" ;;
  vfat)           MOUNT_OPTS="defaults,nofail,noatime,uid=0,gid=$GID,umask=002" ;;
  *)              die "Unsupported filesystem '$FSTYPE' on $PARTITION." ;;
esac

if grep -q "$UUID" /etc/fstab; then
  warn "An fstab entry for UUID $UUID already exists, skipping."
else
  log "Adding entry to /etc/fstab (fstype=$FSTYPE)..."
  echo "UUID=$UUID  $MOUNT_POINT  $FSTYPE  $MOUNT_OPTS  0  2" >> /etc/fstab
fi

log "Mounting all fstab entries..."
mount -a

if [[ "$FSTYPE" == "ext4" || "$FSTYPE" == "ext3" || "$FSTYPE" == "ext2" ]]; then
  log "Setting ownership/permissions for shared access..."
  chown -R root:users "$MOUNT_POINT"
  chmod -R 2775 "$MOUNT_POINT"
fi

if [[ -f /etc/samba/nas-shares.conf ]]; then
  log "Refreshing Samba shares..."
  regenerate_samba_shares
fi

log "Drive mounted at $MOUNT_POINT (UUID=$UUID, fstype=$FSTYPE)."

