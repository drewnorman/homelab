#!/usr/bin/env bash
set -euo pipefail

source_dir="${1:-/media/blue-samsung/02 Personal/Movies}"
destination_dir="${2:-/mnt/media/media/movies}"

proxmox_ssh_host="${PROXMOX_SSH_HOST:-192.168.1.200}"
proxmox_ssh_user="${PROXMOX_SSH_USER:-root}"
proxmox_ssh_key="${PROXMOX_SSH_KEY:-${HOME}/.ssh/root@192.168.1.200}"
local_rsync_sudo="${LOCAL_RSYNC_SUDO:-0}"
radarr_lxc_name="${RADARR_LXC_NAME:-lab-arr}"

# Unprivileged LXC id mapping for container root:media on the Proxmox host.
remote_owner="${REMOTE_OWNER:-100000}"
remote_group="${REMOTE_GROUP:-101000}"

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
radarr_lxc_name_quoted="$(printf '%q' "$radarr_lxc_name")"

printf 'Scanning source: %s\n' "$source_dir"
file_count="$(find "$source_dir" -type f | wc -l | tr -d '[:space:]')"
source_size="$(du -sh "$source_dir" | awk '{print $1}')"
printf 'Found %s files using %s.\n' "$file_count" "$source_size"
printf 'Copying to Proxmox media bind mount: %s:%s\n' "$remote" "$destination_dir"

printf 'Preparing remote destination...\n'
"${ssh_command[@]}" "$remote" \
  "command -v rsync >/dev/null && mkdir -p $remote_destination_dir && chown $remote_owner_quoted:$remote_group_quoted $remote_destination_dir && chmod 775 $remote_destination_dir"

printf 'Verifying Radarr container can access the destination...\n'
"${ssh_command[@]}" "$remote" "$(cat <<'REMOTE'
radarr_vmid="$(pct list 2>/dev/null | awk -v name="$RADARR_LXC_NAME" 'NR>1 && $NF==name {print $1; exit}')"
if [[ -n "$radarr_vmid" ]] && pct status "$radarr_vmid" | grep -q 'status: running'; then
  pct exec "$radarr_vmid" -- sh -c \
    'cd / && runuser -u radarr -- test -r "$1" && runuser -u radarr -- test -x "$1"' \
    sh "$DEST"
fi
REMOTE
)" RADARR_LXC_NAME="$radarr_lxc_name_quoted" DEST="$remote_destination_dir"

printf 'Starting rsync transfer...\n'
"${rsync_command[@]}" \
  -a \
  --whole-file \
  --no-compress \
  --partial \
  --partial-dir=.rsync-partial \
  --info=progress2,stats2,name1 \
  --human-readable \
  --chown="${remote_owner}:${remote_group}" \
  --chmod=D775,F664 \
  -e "$(printf '%q ' "${ssh_command[@]}")" \
  "${source_dir%/}/" \
  "${remote}:${destination_dir%/}/"

printf 'Checking remote disk usage...\n'
"${ssh_command[@]}" "$remote" "df -h $remote_destination_dir"

printf 'Verifying Radarr can read the copied files...\n'
"${ssh_command[@]}" "$remote" "$(cat <<'REMOTE'
radarr_vmid="$(pct list 2>/dev/null | awk -v name="$RADARR_LXC_NAME" 'NR>1 && $NF==name {print $1; exit}')"
if [[ -n "$radarr_vmid" ]] && pct status "$radarr_vmid" | grep -q 'status: running'; then
  unreadable_path="$(pct exec "$radarr_vmid" -- sh -c \
    'cd / && runuser -u radarr -- find "$1" -type f ! -readable -print -quit' \
    sh "$DEST")"
  if [[ -n "$unreadable_path" ]]; then
    printf 'Radarr cannot read: %s\n' "$unreadable_path" >&2
    exit 1
  fi
fi
REMOTE
)" RADARR_LXC_NAME="$radarr_lxc_name_quoted" DEST="$remote_destination_dir"

printf 'Checking Radarr library status...\n'
"${ssh_command[@]}" "$remote" "$(cat <<'REMOTE'
radarr_vmid="$(pct list 2>/dev/null | awk -v name="$RADARR_LXC_NAME" 'NR>1 && $NF==name {print $1; exit}')"
if [[ -n "$radarr_vmid" ]] && pct status "$radarr_vmid" | grep -q 'status: running'; then
  pct exec "$radarr_vmid" -- python3 -c '
import json, urllib.request, xml.etree.ElementTree as ET
api_key = ET.parse("/var/lib/radarr/config.xml").findtext("ApiKey")
req = urllib.request.Request("http://localhost:7878/api/v3/movie", headers={"X-Api-Key": api_key})
movies = json.load(urllib.request.urlopen(req, timeout=30))
missing = [m for m in movies if not m.get("hasFile")]
print("Radarr movies: {} total, {} missing".format(len(movies), len(missing)))
[print("Missing: {} ({}) at {}".format(m.get("title"), m.get("year"), m.get("path"))) for m in missing[:10]]
if len(missing) > 10:
    print("...and {} more missing".format(len(missing) - 10))
'
fi
REMOTE
)" RADARR_LXC_NAME="$radarr_lxc_name_quoted"

printf 'Done.\n'
