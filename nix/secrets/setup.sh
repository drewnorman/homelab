#!/usr/bin/env bash
# Creates and sops-encrypts all homelab secret files.
#
# Prerequisites:
#   1. sops installed: nix shell nixpkgs#sops nixpkgs#age nixpkgs#ssh-to-age
#   2. Your operator age key added to .sops.yaml (see instructions there)
#   3. .env populated at the repo root
#   4. After first `tofu apply`, host age keys added to .sops.yaml
#
# Re-run safely — existing encrypted files are not overwritten unless you
# pass --force.
set -euo pipefail

REPO_ROOT="$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"
SECRETS_DIR="$REPO_ROOT/nix/secrets"
FORCE="${1:-}"

# ---- helpers ----------------------------------------------------------------

die()  { echo "error: $*" >&2; exit 1; }
info() { echo "==> $*"; }

require_cmd() {
  command -v "$1" &>/dev/null || die "'$1' not found — run: nix shell nixpkgs#$1"
}

require_cmd sops
require_cmd openssl

# Check .sops.yaml has been initialised (operator key placeholder replaced)
if grep -q 'REPLACE_WITH_YOUR_AGE_PUBLIC_KEY' "$SECRETS_DIR/.sops.yaml"; then
  die ".sops.yaml still has placeholder keys. See the setup instructions inside it."
fi

# Source real secrets from .env
ENV_FILE="$REPO_ROOT/.env"
[[ -f "$ENV_FILE" ]] || die ".env not found at $REPO_ROOT"
set -a; source "$ENV_FILE"; set +a

# ---- per-file helpers -------------------------------------------------------

# encrypt_secret FILE YAML_CONTENT
# Writes plaintext YAML to FILE, encrypts it in-place with sops, then
# wipes the plaintext from disk. Skips if FILE exists unless --force.
encrypt_secret() {
  local file="$1"
  local content="$2"
  if [[ -f "$file" && "$FORCE" != "--force" ]]; then
    info "skipping $file (already exists; pass --force to overwrite)"
    return
  fi
  info "encrypting $(basename "$file")"
  echo "$content" > "$file"
  sops --encrypt --in-place "$file"
}

cd "$SECRETS_DIR"

# ---- edge -------------------------------------------------------------------
# Cloudflare DNS API token for Caddy's DNS-01 ACME challenge.
# Value must be in KEY=VALUE format (systemd EnvironmentFile).

: "${CLOUDFLARE_DNS_API_TOKEN:?CLOUDFLARE_DNS_API_TOKEN not set in .env}"

encrypt_secret edge.yaml \
"cloudflare-dns-api-token: \"CLOUDFLARE_DNS_API_TOKEN=${CLOUDFLARE_DNS_API_TOKEN}\""

# ---- lldap ------------------------------------------------------------------

if [[ -z "${LLDAP_ADMIN_PASSWORD:-}" ]]; then
  read -rsp "LLDAP admin password (will also be used as Authelia bind password): " LLDAP_ADMIN_PASSWORD
  echo
fi
[[ -n "$LLDAP_ADMIN_PASSWORD" ]] || die "LLDAP_ADMIN_PASSWORD must not be empty"

LLDAP_JWT_SECRET=$(openssl rand -hex 32)

encrypt_secret lldap.yaml "$(cat <<EOF
lldap-jwt-secret: "${LLDAP_JWT_SECRET}"
lldap-admin-password: "${LLDAP_ADMIN_PASSWORD}"
EOF
)"

# ---- authelia ---------------------------------------------------------------

AUTHELIA_JWT_SECRET=$(openssl rand -hex 32)
AUTHELIA_SESSION_SECRET=$(openssl rand -hex 32)
AUTHELIA_STORAGE_ENCRYPTION_KEY=$(openssl rand -hex 32)

encrypt_secret authelia.yaml "$(cat <<EOF
authelia-jwt-secret: "${AUTHELIA_JWT_SECRET}"
authelia-session-secret: "${AUTHELIA_SESSION_SECRET}"
authelia-storage-encryption-key: "${AUTHELIA_STORAGE_ENCRYPTION_KEY}"
authelia-lldap-password: "${LLDAP_ADMIN_PASSWORD}"
EOF
)"

# ---- qbittorrent ------------------------------------------------------------
# Paste your Proton VPN WireGuard config when prompted (the full [Interface]/
# [Peer] block as plain text, not base64). Press Ctrl-D when done.

if [[ ! -f qbittorrent.yaml || "$FORCE" == "--force" ]]; then
  info "Paste your Proton VPN WireGuard config (Ctrl-D to finish):"
  WG_CONFIG=$(cat)
  encrypt_secret qbittorrent.yaml "$(cat <<EOF
protonvpn-wireguard-config: |
$(echo "$WG_CONFIG" | sed 's/^/  /')
EOF
)"
else
  info "skipping qbittorrent.yaml (already exists; pass --force to overwrite)"
fi

info "done — all secrets encrypted in $SECRETS_DIR"
info "Next: add host age keys to .sops.yaml, then run: sops updatekeys <file>.yaml"
