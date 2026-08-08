#!/usr/bin/env bash
# Create the one-time OpenAI workload key and hand it directly to sops.
set -euo pipefail

umask 077

REPO_ROOT="$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"
OPENAI_ROOT="$REPO_ROOT/terraform/openai"
SECRET_FILE="$REPO_ROOT/nix/secrets/open-webui.yaml"
ADMIN_SECRET_FILE="$REPO_ROOT/nix/secrets/openai-admin.yaml"
PLACEHOLDER="replace-with-project-service-account-key"
ROTATE=false

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

info() {
  printf '==> %s\n' "$*"
}

usage() {
  cat <<'EOF'
Usage: scripts/bootstrap-openai-key.sh [--rotate]

Without --rotate, the script only replaces the known placeholder. --rotate
explicitly selects the key-rotation workflow when a real key is already stored.
The old remote key is intentionally left active for rollback and must be revoked
after the new key has been deployed and verified.
EOF
}

case "${1:-}" in
  "")
    ;;
  --rotate)
    ROTATE=true
    ;;
  -h|--help)
    usage
    exit 0
    ;;
  *)
    usage >&2
    exit 2
    ;;
esac

for command in curl jq sops tofu; do
  command -v "$command" >/dev/null || die "'$command' is required"
done

if [[ -z "${OPENAI_ADMIN_KEY:-}" ]]; then
  [[ -f "$ADMIN_SECRET_FILE" ]] ||
    die "OPENAI_ADMIN_KEY is unset and $ADMIN_SECRET_FILE is missing"
  OPENAI_ADMIN_KEY="$(sops --decrypt --extract '["openai-admin-key"]' "$ADMIN_SECRET_FILE")" ||
    die "cannot decrypt $ADMIN_SECRET_FILE"
fi
[[ "$OPENAI_ADMIN_KEY" == sk-* ]] || die "OPENAI_ADMIN_KEY has an unexpected format"
[[ -f "$SECRET_FILE" ]] || die "missing sops file: $SECRET_FILE"

current_key="$(sops --decrypt --extract '["openai-api-key"]' "$SECRET_FILE")" ||
  die "cannot decrypt $SECRET_FILE"
if [[ "$current_key" != "$PLACEHOLDER" && "$ROTATE" != true ]]; then
  die "openai-api-key is not the known placeholder; pass --rotate to select the explicit rotation workflow"
fi
unset current_key

project_id="$(tofu -chdir="$OPENAI_ROOT" output -raw project_id)"
service_account_id="$(tofu -chdir="$OPENAI_ROOT" output -raw service_account_id)"
[[ "$project_id" == proj_* ]] || die "unexpected project ID from OpenTofu output"
[[ "$service_account_id" == svc_acct_* || "$service_account_id" == user-* ]] ||
  die "unexpected service-account ID from OpenTofu output"

work_dir="$(mktemp -d "${TMPDIR:-/tmp}/openai-key-bootstrap.XXXXXX")"
chmod 0700 "$work_dir"
response_file="$work_dir/create-response.json"
value_file="$work_dir/key-value.json"
encrypted_backup="$work_dir/open-webui.yaml.encrypted"
cp -- "$SECRET_FILE" "$encrypted_backup"

new_key_id=""
handoff_complete=false

revoke_new_key() {
  if [[ -z "$new_key_id" && -s "$response_file" ]]; then
    new_key_id="$(jq -r '.id // empty' "$response_file" 2>/dev/null || true)"
  fi
  [[ -n "$new_key_id" ]] || return 0
  info "revoking newly created key after failed sops handoff"
  curl --silent --show-error --fail-with-body \
    --request DELETE \
    --header "Authorization: Bearer $OPENAI_ADMIN_KEY" \
    --header "Content-Type: application/json" \
    "https://api.openai.com/v1/organization/projects/$project_id/api_keys/$new_key_id" \
    >/dev/null || printf 'warning: automatic key revocation failed; revoke key %s manually\n' "$new_key_id" >&2
}

cleanup() {
  status=$?
  if [[ "$status" -ne 0 && "$handoff_complete" != true ]]; then
    cp -- "$encrypted_backup" "$SECRET_FILE"
    revoke_new_key
  fi
  rm -f -- "$response_file" "$value_file" "$encrypted_backup"
  rmdir -- "$work_dir" 2>/dev/null || true
  exit "$status"
}
trap cleanup EXIT HUP INT TERM

request_body="$(
  jq -cn '{
    name: "homelab-ai-production-open-webui",
    scopes: ["api.responses.write"]
  }'
)"

info "creating one service-account API key"
curl --silent --show-error --fail-with-body \
  --request POST \
  --header "Authorization: Bearer $OPENAI_ADMIN_KEY" \
  --header "Content-Type: application/json" \
  --data "$request_body" \
  --output "$response_file" \
  "https://api.openai.com/v1/organization/projects/$project_id/service_accounts/$service_account_id/api_keys"
unset request_body

new_key_id="$(jq -er '.id | select(type == "string" and length > 0)' "$response_file")"
jq -e '.value | select(type == "string" and startswith("sk-"))' "$response_file" \
  >"$value_file"

info "updating only openai-api-key in the encrypted sops file"
sops set --value-file "$SECRET_FILE" '["openai-api-key"]' "$value_file"

stored_key="$(sops --decrypt --extract '["openai-api-key"]' "$SECRET_FILE")"
created_key="$(jq -r '.value' "$response_file")"
[[ "$stored_key" == "$created_key" ]] || die "sops verification did not match the newly created key"
unset stored_key created_key

handoff_complete=true
info "encrypted key handoff verified; created key ID: $new_key_id"
if [[ "$ROTATE" == true ]]; then
  info "rotation selected: deploy and verify the new key, then revoke the old remote key"
fi
