#!/usr/bin/env bash
# Enables ufw with a safe default: allow SSH + Samba, deny everything else inbound.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
source lib/common.sh

require_root

log "Setting default policies (deny incoming, allow outgoing)..."
ufw default deny incoming
ufw default allow outgoing

log "Allowing SSH so you don't lock yourself out..."
ufw allow ssh

log "Allowing Samba (445/139) and mDNS (5353) for raspberrypi.local discovery..."
ufw allow samba
ufw allow 5353/udp

if ! ufw status | grep -q "Status: active"; then
  confirm "Enable ufw now?" && ufw --force enable
fi

ufw status verbose
