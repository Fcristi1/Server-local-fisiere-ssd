#!/usr/bin/env bash
# Manages Samba/NAS user accounts directly on the Pi (create, set password, list, remove).
#
# Usage:
#   sudo ./03-manage-nas-users.sh add    --username nasuser [--password 'secret']
#   sudo ./03-manage-nas-users.sh passwd --username nasuser [--password 'secret']
#   sudo ./03-manage-nas-users.sh list
#   sudo ./03-manage-nas-users.sh remove --username nasuser
#
# Omit --password to be prompted interactively (recommended). Passing --password
# is handy for scripting but ends up in shell history, so prefer the prompt on a
# machine you don't fully trust.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
source lib/common.sh

require_root

usage() { grep '^#' "$0" | sed 's/^# \{0,1\}//' | head -n 11; exit 1; }

[[ $# -ge 1 ]] || usage
ACTION="$1"; shift

USERNAME=""
PASSWORD=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --username) USERNAME="$2"; shift 2 ;;
    --password) PASSWORD="$2"; shift 2 ;;
    -h|--help) usage ;;
    *) die "Unknown argument: $1" ;;
  esac
done

ensure_group() {
  if ! getent group users >/dev/null; then
    log "Creating shared 'users' group..."
    groupadd users
  fi
}

set_smb_password() {
  local user="$1"
  if [[ -n "$PASSWORD" ]]; then
    log "Setting Samba password for $user (non-interactive)..."
    printf '%s\n%s\n' "$PASSWORD" "$PASSWORD" | smbpasswd -s -a "$user"
  else
    log "Set the Samba password for $user (this is what the phone/PC will use):"
    smbpasswd -a "$user"
  fi
  smbpasswd -e "$user"
}

case "$ACTION" in
  add)
    [[ -n "$USERNAME" ]] || die "Missing --username."
    ensure_group

    if id "$USERNAME" >/dev/null 2>&1; then
      log "System user $USERNAME already exists."
    else
      log "Creating system user $USERNAME (no shell login, group 'users')..."
      useradd --system --create-home --shell /usr/sbin/nologin --gid users "$USERNAME"
    fi

    set_smb_password "$USERNAME"
    log "Done. Use username '$USERNAME' + the password you just set from your SMB client."
    ;;

  passwd)
    [[ -n "$USERNAME" ]] || die "Missing --username."
    id "$USERNAME" >/dev/null 2>&1 || die "System user $USERNAME does not exist. Use 'add' first."
    set_smb_password "$USERNAME"
    log "Password updated for $USERNAME."
    ;;

  list)
    log "Samba users:"
    pdbedit -L 2>/dev/null | cut -d: -f1
    ;;

  remove)
    [[ -n "$USERNAME" ]] || die "Missing --username."
    confirm "Remove Samba access and delete system user '$USERNAME'?" || die "Aborted."
    smbpasswd -x "$USERNAME" 2>/dev/null || true
    if id "$USERNAME" >/dev/null 2>&1; then
      userdel -r "$USERNAME" 2>/dev/null || userdel "$USERNAME"
    fi
    log "Removed $USERNAME."
    ;;

  *)
    usage
    ;;
esac
