#!/usr/bin/env bash
set -euo pipefail

source_dir="${1:-${HOME}/videos}"
destination_dir="${2:-/srv/media/movies}"

jellyfin_ssh_host="${JELLYFIN_SSH_HOST:-192.168.1.230}"
jellyfin_ssh_user="${JELLYFIN_SSH_USER:-root}"
jellyfin_ssh_key="${JELLYFIN_SSH_KEY:-${HOME}/.ssh/root@jellyfin.lab.adre.me}"

if ! command -v rsync >/dev/null 2>&1; then
  printf 'rsync is required locally.\n' >&2
  exit 1
fi

if [[ ! -d "$source_dir" ]]; then
  printf 'Source directory does not exist: %s\n' "$source_dir" >&2
  exit 1
fi

ssh_command=(
  ssh
  -F /dev/null
  -i "$jellyfin_ssh_key"
  -o IdentitiesOnly=yes
  -o StrictHostKeyChecking=accept-new
)

remote="${jellyfin_ssh_user}@${jellyfin_ssh_host}"

"${ssh_command[@]}" "$remote" "command -v rsync >/dev/null && mkdir -p '$destination_dir'"

rsync \
  -a \
  --whole-file \
  --no-compress \
  --partial \
  --partial-dir=.rsync-partial \
  --info=progress2 \
  --human-readable \
  --chown=jellyfin:jellyfin \
  -e "$(printf '%q ' "${ssh_command[@]}")" \
  "${source_dir%/}/" \
  "${remote}:${destination_dir%/}/"

"${ssh_command[@]}" "$remote" "chown -R jellyfin:jellyfin '$destination_dir' && df -h '$destination_dir'"
