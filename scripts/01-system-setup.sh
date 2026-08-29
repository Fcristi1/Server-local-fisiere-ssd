#!/usr/bin/env bash
# Updates the OS and installs the packages needed for a Samba/NFS NAS on Raspberry Pi OS.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
source lib/common.sh

require_root

log "Updating package lists and upgrading installed packages..."
apt-get update
apt-get -y upgrade

log "Installing NAS packages (samba, disk tools, monitoring)..."
apt-get -y install \
  samba samba-common-bin \
  nfs-kernel-server \
  parted gdisk exfatprogs ntfs-3g e2fsprogs \
  smartmontools \
  htop tmux \
  ufw \
  avahi-daemon

log "Enabling and starting smartd (disk health monitoring)..."
systemctl enable --now smartmontools.service

log "Enabling avahi-daemon so the Pi is reachable as raspberrypi.local..."
systemctl enable --now avahi-daemon

log "Done. Reboot recommended if the kernel was updated: sudo reboot"
