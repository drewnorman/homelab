#!/usr/bin/env bash
set -euo pipefail

# Joins this machine to the homelab Tailscale network.
#
# Requires --accept-dns so that Tailscale split DNS resolves *.lab.adre.me
# through AdGuard, and --accept-routes so that traffic to the advertised
# AdGuard and edge subnets is routed through the tailnet.

hostname="${TAILSCALE_HOSTNAME:-${HOSTNAME%%.*}}"

if ! command -v tailscale >/dev/null 2>&1; then
  printf 'tailscale is not installed.\n' >&2
  printf '  Arch:   sudo pacman -S tailscale\n' >&2
  printf '  Debian: curl -fsSL https://tailscale.com/install.sh | sh\n' >&2
  printf '  macOS:  brew install tailscale\n' >&2
  exit 1
fi

if ! tailscale status >/dev/null 2>&1; then
  printf 'tailscaled is not running. Start it first:\n' >&2
  printf '  sudo systemctl enable --now tailscaled\n' >&2
  exit 1
fi

printf 'Joining tailnet as "%s"...\n' "${hostname}"

sudo tailscale up \
  --hostname="${hostname}" \
  --accept-dns=true \
  --accept-routes=true

printf '\nStatus:\n'
tailscale status
