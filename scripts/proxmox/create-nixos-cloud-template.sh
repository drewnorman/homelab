#!/usr/bin/env bash
# Create a reusable NixOS cloud-init VM template on a Proxmox node.
#
# Run this on the Proxmox host, not on your workstation:
#   ssh root@192.168.1.200
#   bash create-nixos-cloud-template.sh
#
# The Terraform variable core_vm_template_vm_id must match TEMPLATE_VMID.
set -euo pipefail

TEMPLATE_VMID="${TEMPLATE_VMID:-9000}"
TEMPLATE_NAME="${TEMPLATE_NAME:-nixos-25.05-cloudinit}"
STORAGE="${STORAGE:-local-lvm}"
BRIDGE="${BRIDGE:-vmbr0}"
MEMORY_MB="${MEMORY_MB:-2048}"
CORES="${CORES:-2}"
IMAGE_DIR="${IMAGE_DIR:-/var/lib/vz/template/iso}"
IMAGE_NAME="${IMAGE_NAME:-nixos-25.05-proxmox-cloud.qcow2}"
IMAGE_URL="${IMAGE_URL:-https://hydra.nixos.org/job/nixos/release-25.05/nixos.proxmoxCloudImage.x86_64-linux/latest/download-by-type/file/disk-image}"
IMAGE_PATH="${IMAGE_DIR}/${IMAGE_NAME}"

die() {
  echo "error: $*" >&2
  exit 1
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "'$1' is required"
}

require_cmd qm
require_cmd wget

[[ "$(id -u)" -eq 0 ]] || die "run as root on the Proxmox host"

if qm status "${TEMPLATE_VMID}" >/dev/null 2>&1; then
  die "VMID ${TEMPLATE_VMID} already exists; set TEMPLATE_VMID to an unused ID"
fi

mkdir -p "${IMAGE_DIR}"

if [[ ! -f "${IMAGE_PATH}" ]]; then
  echo "Downloading ${IMAGE_URL}"
  wget --output-document="${IMAGE_PATH}.tmp" "${IMAGE_URL}"
  mv "${IMAGE_PATH}.tmp" "${IMAGE_PATH}"
else
  echo "Using existing image ${IMAGE_PATH}"
fi

qm create "${TEMPLATE_VMID}" \
  --name "${TEMPLATE_NAME}" \
  --memory "${MEMORY_MB}" \
  --cores "${CORES}" \
  --net0 "virtio,bridge=${BRIDGE}" \
  --ostype l26 \
  --scsihw virtio-scsi-pci \
  --agent enabled=1

qm importdisk "${TEMPLATE_VMID}" "${IMAGE_PATH}" "${STORAGE}"
qm set "${TEMPLATE_VMID}" \
  --scsi0 "${STORAGE}:vm-${TEMPLATE_VMID}-disk-0,discard=on,ssd=1" \
  --ide2 "${STORAGE}:cloudinit" \
  --boot order=scsi0 \
  --serial0 socket \
  --vga serial0 \
  --ipconfig0 ip=dhcp

qm template "${TEMPLATE_VMID}"

cat <<EOF
Created Proxmox template ${TEMPLATE_NAME} (${TEMPLATE_VMID}).

Set this in terraform/terraform.tfvars:
  core_vm_template_vm_id = ${TEMPLATE_VMID}
EOF
