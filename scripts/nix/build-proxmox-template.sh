#!/usr/bin/env bash
# Build the NixOS Proxmox VMA template image with Podman.
set -euo pipefail

REPO_ROOT="$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"
OUT_LINK="${OUT_LINK:-$REPO_ROOT/nix/result-proxmox-template}"
NIX_IMAGE="${NIX_IMAGE:-docker.io/nixos/nix:latest}"
GENERATOR_FLAKE="${GENERATOR_FLAKE:-github:nix-community/nixos-generators}"

cd "$REPO_ROOT"

PODMAN_KVM_ARGS=()
NIX_KVM_ARGS=()
if [[ -e /dev/kvm ]]; then
  PODMAN_KVM_ARGS=(--device /dev/kvm)
  NIX_KVM_ARGS=(--option system-features "kvm benchmark big-parallel nixos-test")
else
  echo "warning: /dev/kvm not found; Proxmox image builds usually require KVM" >&2
fi

podman run --rm \
  "${PODMAN_KVM_ARGS[@]}" \
  -v "$REPO_ROOT:/workspace" \
  -w /workspace/nix \
  "$NIX_IMAGE" \
  nix run \
    --extra-experimental-features nix-command \
    --extra-experimental-features flakes \
    "$GENERATOR_FLAKE" -- \
    --format proxmox \
    --configuration /workspace/nix/images/proxmox-template.nix \
    --out-link /workspace/nix/result-proxmox-template \
    "${NIX_KVM_ARGS[@]}"

echo
echo "Built Proxmox image:"
find "$OUT_LINK" -type f -name '*.vma.zst' -print
