#!/usr/bin/env bash
# Build the NixOS Proxmox VMA template image with Podman.
set -euo pipefail

REPO_ROOT="$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"
OUT_LINK="${OUT_LINK:-$REPO_ROOT/nix/result-proxmox-template}"
OUT_DIR="${OUT_DIR:-$REPO_ROOT/nix/artifacts/proxmox-template}"
NIX_IMAGE="${NIX_IMAGE:-docker.io/nixos/nix:latest}"

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
  bash -euo pipefail -c '
    nix build \
      --extra-experimental-features nix-command \
      --extra-experimental-features flakes \
      /workspace/nix#proxmox-template \
      --out-link /workspace/nix/result-proxmox-template \
      "$@"

    mkdir -p /workspace/nix/artifacts/proxmox-template
    copied="$(
      find -L /workspace/nix/result-proxmox-template \
        -maxdepth 1 \
        -type f \
        -name "*.vma.zst" \
        -exec cp -f {} /workspace/nix/artifacts/proxmox-template/ \; \
        -print
    )"

    if [[ -z "$copied" ]]; then
      echo "error: Proxmox image build did not produce a .vma.zst artifact" >&2
      exit 1
    fi
  ' bash "${NIX_KVM_ARGS[@]}"

echo
echo "Built Proxmox image:"
find "$OUT_DIR" -type f -name '*.vma.zst' -print
