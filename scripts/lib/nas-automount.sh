#!/usr/bin/env bash
# Called by the udev rule (99-nas-automount.rules) whenever a USB drive is plugged
# or unplugged. Auto-mounts already-formatted partitions under /srv/nas and keeps
# the Samba shares in sync — no manual steps needed after a drive has a filesystem.
#
# Args: $1 = kernel device name (e.g. sda1), ACTION/ID_FS_TYPE/ID_FS_LABEL come from udev env.
set -uo pipefail

KNAME="$1"
DEVNAME="/dev/$KNAME"
ACTION="${ACTION:-add}"
BASE_DIR="/srv/nas"
SHARES_INCLUDE="/etc/samba/nas-shares.conf"
STATE_DIR="/run/nas-automount"
LOG="/var/log/nas-automount.log"

mkdir -p "$STATE_DIR"
exec >> "$LOG" 2>&1
echo "$(date -Is) action=$ACTION dev=$DEVNAME"

regenerate_shares() {
  : > "$SHARES_INCLUDE"
  for dir in "$BASE_DIR"/*/; do
    [[ -d "$dir" ]] || continue
    name="$(basename "$dir")"
    cat >> "$SHARES_INCLUDE" <<EOF

[$name]
   path = $dir
   valid users = @users
   read only = no
   browsable = yes
   guest ok = no
   create mask = 0664
   directory mask = 2775
   veto files = /lost+found/
   delete veto files = no
EOF
  done
  smbcontrol smbd reload-config 2>/dev/null || systemctl reload smbd 2>/dev/null || true
}

if [[ "$ACTION" == "remove" ]]; then
  STATE_FILE="$STATE_DIR/$KNAME"
  if [[ -f "$STATE_FILE" ]]; then
    MOUNT_POINT="$(cat "$STATE_FILE")"
    echo "Unmounting $MOUNT_POINT (device removed)"
    umount -l "$MOUNT_POINT" 2>/dev/null || true
    rmdir "$MOUNT_POINT" 2>/dev/null || true
    rm -f "$STATE_FILE"
    regenerate_shares
  fi
  exit 0
fi

# --- ACTION == add ---
[[ -b "$DEVNAME" ]] || { echo "$DEVNAME is not a block device, skipping"; exit 0; }

FSTYPE="$(blkid -s TYPE -o value "$DEVNAME" 2>/dev/null || true)"
if [[ -z "$FSTYPE" ]]; then
  echo "$DEVNAME has no filesystem yet. Plug-and-play needs a one-time format:"
  echo "  sudo ./scripts/02-prepare-disk.sh --device $DEVNAME --label <name> --format"
  logger -t nas-automount "New unformatted drive $DEVNAME detected. Run 02-prepare-disk.sh --format to initialize it."
  exit 0
fi

LABEL="$(blkid -s LABEL -o value "$DEVNAME" 2>/dev/null || true)"
NAME="${LABEL:-$KNAME}"
MOUNT_POINT="$BASE_DIR/$NAME"

if mountpoint -q "$MOUNT_POINT" 2>/dev/null; then
  echo "$MOUNT_POINT already mounted, skipping"
  exit 0
fi

if ! getent group users >/dev/null; then
  groupadd users
fi
GID="$(getent group users | cut -d: -f3)"

case "$FSTYPE" in
  ext4|ext3|ext2) MOUNT_OPTS="rw,nofail,noatime" ;;
  ntfs|exfat|vfat) MOUNT_OPTS="rw,nofail,noatime,uid=0,gid=$GID,umask=002" ;;
  *) echo "Unsupported filesystem '$FSTYPE' on $DEVNAME, skipping"; exit 0 ;;
esac

mkdir -p "$MOUNT_POINT"
echo "Mounting $DEVNAME ($FSTYPE) at $MOUNT_POINT"
if ! mount -t "$FSTYPE" -o "$MOUNT_OPTS" "$DEVNAME" "$MOUNT_POINT"; then
  echo "Mount failed for $DEVNAME"
  rmdir "$MOUNT_POINT" 2>/dev/null || true
  exit 1
fi

if [[ "$FSTYPE" == "ext4" || "$FSTYPE" == "ext3" || "$FSTYPE" == "ext2" ]]; then
  chown root:users "$MOUNT_POINT"
  chmod 2775 "$MOUNT_POINT"
fi

echo "$MOUNT_POINT" > "$STATE_DIR/$KNAME"
regenerate_shares
echo "Done: $NAME shared from $MOUNT_POINT"
