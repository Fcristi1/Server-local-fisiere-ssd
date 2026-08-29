#!/usr/bin/env bash
# Shared helpers sourced by the other scripts in this repo.
set -euo pipefail

log()  { printf '\033[1;32m[+]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[!]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[x]\033[0m %s\n' "$*" >&2; exit 1; }

require_root() {
  [[ $EUID -eq 0 ]] || die "This script must be run as root (use sudo)."
}

confirm() {
  local prompt="$1"
  local reply
  read -r -p "$prompt [y/N] " reply
  [[ "$reply" =~ ^[Yy]$ ]]
}

# Rebuilds /etc/samba/nas-shares.conf from every directory under /srv/nas and
# reloads smbd so the change takes effect without dropping active connections.
regenerate_samba_shares() {
  local base_dir="/srv/nas"
  local shares_include="/etc/samba/nas-shares.conf"

  [[ -d "$base_dir" ]] || return 0
  : > "$shares_include"
  for dir in "$base_dir"/*/; do
    [[ -d "$dir" ]] || continue
    local name
    name="$(basename "$dir")"
    cat >> "$shares_include" <<EOF

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

