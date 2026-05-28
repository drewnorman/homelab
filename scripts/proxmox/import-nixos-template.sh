#!/usr/bin/env bash
# Import a generated NixOS Proxmox VMA image as a reusable VM template.
#
# Run this on the Proxmox host after copying the generated .vma.zst file there.
set -euo pipefail

VMA_PATH="${1:-}"
TEMPLATE_VMID="${TEMPLATE_VMID:-9000}"
TEMPLATE_NAME="${TEMPLATE_NAME:-nixos-25.05-cloudinit}"
STORAGE="${STORAGE:-local-lvm}"
BRIDGE="${BRIDGE:-vmbr0}"

die() {
  echo "error: $*" >&2
  exit 1
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "'$1' is required"
}

require_cmd qm

[[ "$(id -u)" -eq 0 ]] || die "run as root on the Proxmox host"
[[ -n "$VMA_PATH" ]] || die "usage: $0 /path/to/nixos-template.vma.zst"
[[ -f "$VMA_PATH" ]] || die "image not found: $VMA_PATH"

if qm status "$TEMPLATE_VMID" >/dev/null 2>&1; then
  die "VMID ${TEMPLATE_VMID} already exists; set TEMPLATE_VMID to an unused ID"
fi

qmrestore "$VMA_PATH" "$TEMPLATE_VMID" --unique true --storage "$STORAGE"

qm_set_args=(
  --name "$TEMPLATE_NAME" \
  --net0 "virtio,bridge=${BRIDGE}" \
  --agent enabled=1 \
  --ipconfig0 ip=dhcp
)

if ! qm config "$TEMPLATE_VMID" | grep -q '^ide2: .*cloudinit'; then
  qm_set_args+=(--ide2 "${STORAGE}:cloudinit")
fi

qm set "$TEMPLATE_VMID" "${qm_set_args[@]}"

qm template "$TEMPLATE_VMID"

cat <<EOF
Created Proxmox template ${TEMPLATE_NAME} (${TEMPLATE_VMID}).

Set this in terraform/terraform.tfvars:
  core_vm_template_vm_id = ${TEMPLATE_VMID}
EOF
