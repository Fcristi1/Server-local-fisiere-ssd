#!/usr/bin/env bash
# Creates a dedicated system user for NAS access and adds it as a Samba user.
#
# Usage: sudo ./03-create-nas-user.sh --username nasuser
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
source lib/common.sh

require_root

USERNAME=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --username) USERNAME="$2"; shift 2 ;;
    -h|--help) echo "Usage: $0 --username <name>"; exit 1 ;;
    *) die "Unknown argument: $1" ;;
  esac
done
[[ -n "$USERNAME" ]] || die "Missing --username."

if ! getent group users >/dev/null; then
  groupadd users
fi

if id "$USERNAME" >/dev/null 2>&1; then
  log "System user $USERNAME already exists."
else
  log "Creating system user $USERNAME (no shell login, group 'users')..."
  useradd --system --create-home --shell /usr/sbin/nologin --gid users "$USERNAME"
fi

log "Set the Samba password for $USERNAME (this is what the phone/PC will use):"
smbpasswd -a "$USERNAME"
smbpasswd -e "$USERNAME"

log "Done. Use this username + the password you just set from your SMB client."
