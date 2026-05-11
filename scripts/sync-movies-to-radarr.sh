#!/usr/bin/env bash
set -euo pipefail

source_dir="${1:-/media/blue-samsung/02 Personal/Movies}"
destination_dir="${2:-/mnt/media/media/movies}"

proxmox_ssh_host="${PROXMOX_SSH_HOST:-192.168.1.200}"
proxmox_ssh_user="${PROXMOX_SSH_USER:-root}"
proxmox_ssh_key="${PROXMOX_SSH_KEY:-${HOME}/.ssh/root@192.168.1.200}"
local_rsync_sudo="${LOCAL_RSYNC_SUDO:-0}"

# Unprivileged LXC id mapping for container root:media.
remote_owner="${RADARR_REMOTE_OWNER:-100000}"
remote_group="${RADARR_REMOTE_GROUP:-101000}"

if ! command -v rsync >/dev/null 2>&1; then
  printf 'rsync is required locally.\n' >&2
  exit 1
fi

if [[ ! -d "$source_dir" ]]; then
  printf 'Source directory does not exist: %s\n' "$source_dir" >&2
  exit 1
fi

rsync_command=(rsync)
if [[ "$local_rsync_sudo" == "1" ]]; then
  if ! command -v sudo >/dev/null 2>&1; then
    printf 'sudo is required when LOCAL_RSYNC_SUDO=1.\n' >&2
    exit 1
  fi

  sudo -v
  rsync_command=(sudo rsync)
else
  unreadable_paths="$(
    find "$source_dir" \( ! -readable -o \( -type d ! -executable \) \) -print 2>/dev/null | head -n 20 || true
  )"

  if [[ -n "$unreadable_paths" ]]; then
    printf 'Some source paths are not readable by the current user:\n' >&2
    printf '%s\n' "$unreadable_paths" >&2
    printf '\nFix the local permissions, or rerun with LOCAL_RSYNC_SUDO=1 to read the source with sudo.\n' >&2
    exit 1
  fi
fi

ssh_command=(
  ssh
  -F /dev/null
  -i "$proxmox_ssh_key"
  -o IdentitiesOnly=yes
  -o StrictHostKeyChecking=accept-new
)

remote="${proxmox_ssh_user}@${proxmox_ssh_host}"
remote_destination_dir="$(printf '%q' "$destination_dir")"
remote_owner_quoted="$(printf '%q' "$remote_owner")"
remote_group_quoted="$(printf '%q' "$remote_group")"

printf 'Syncing movies from %s to %s:%s\n' "$source_dir" "$remote" "$destination_dir"

"${ssh_command[@]}" "$remote" \
  "command -v rsync >/dev/null && mkdir -p $remote_destination_dir && chown $remote_owner_quoted:$remote_group_quoted $remote_destination_dir"

"${rsync_command[@]}" \
  -a \
  --whole-file \
  --no-compress \
  --partial \
  --partial-dir=.rsync-partial \
  --info=progress2 \
  --human-readable \
  --chown="${remote_owner}:${remote_group}" \
  --chmod=D775,F664 \
  -e "$(printf '%q ' "${ssh_command[@]}")" \
  "${source_dir%/}/" \
  "${remote}:${destination_dir%/}/"

"${ssh_command[@]}" "$remote" \
  "chown -R $remote_owner_quoted:$remote_group_quoted $remote_destination_dir && find $remote_destination_dir -type d -exec chmod 775 {} + && find $remote_destination_dir -type f -exec chmod 664 {} + && df -h $remote_destination_dir"
