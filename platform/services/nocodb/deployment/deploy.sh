#!/usr/bin/env bash
# deploy.sh — Deploy NocoDB with programmatic admin + API token creation
# Idempotent: safe to re-run on an existing deployment.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$(dirname "$(dirname "$(dirname "$SCRIPT_DIR")")")/lib"
source "${LIB_DIR}/common.sh"
source "${LIB_DIR}/bao-client.sh"

SECRETS_DIR="${SCRIPT_DIR}/secrets"
CONFIG_DIR="${SCRIPT_DIR}/config"
NOCODB_URL="${NOCODB_URL:-http://localhost:8181}"
OPENBAO_ADDR="${OPENBAO_ADDR:-http://127.0.0.1:8200}"
ADMIN_EMAIL="${NOCODB_ADMIN_EMAIL:-admin@uhstray.io}"

# ── Step 1: Generate secrets & env file ───────────────────────────────────────

step_generate_secrets() {
  info "Step 1: Generating NocoDB secrets..."
  mkdir -p "$SECRETS_DIR"

  # Generate admin password if not already set
  local admin_pass
  admin_pass=$(get_secret "$SECRETS_DIR" nocodb_admin_password)
  needs_gen "$admin_pass" && admin_pass=$(gen_secret 16 32)
  put_secret "$SECRETS_DIR" nocodb_admin_password "$admin_pass"

  generate_nocodb_env "${CONFIG_DIR}/nocodb.env" "$SECRETS_DIR"
}

# ── Step 2: Start services ────────────────────────────────────────────────────

step_start_services() {
  info "Step 2: Starting NocoDB services..."
  cd "$SCRIPT_DIR"
  compose up -d
  wait_for_http "${NOCODB_URL}/api/v1/health" "NocoDB" 120
}

# ── Step 3: Bootstrap admin user + API token ──────────────────────────────────

step_bootstrap_credentials() {
  info "Step 3: Bootstrapping NocoDB credentials..."
  local admin_pass api_token
  admin_pass=$(get_secret "$SECRETS_DIR" nocodb_admin_password)

  # Check if API token already exists
  api_token=$(get_secret "$SECRETS_DIR" nocodb_api_token)
  if ! needs_gen "$api_token"; then
    info "  API token already exists — skipping bootstrap."
    return 0
  fi

  # Try signup (first boot — no users exist yet)
  local signup_response jwt_token auth_payload
  auth_payload=$(jq -n --arg email "$ADMIN_EMAIL" --arg pass "$admin_pass" \
    '{"email":$email,"password":$pass}')

  signup_response=$(curl -sf -X POST "${NOCODB_URL}/api/v1/auth/user/signup" \
    -H "Content-Type: application/json" \
    --data-raw "$auth_payload" 2>/dev/null) || true

  if [ -n "$signup_response" ]; then
    jwt_token=$(echo "$signup_response" | jq -r '.token // empty')
    if [ -n "$jwt_token" ]; then
      info "  Admin user created via signup."
    fi
  fi

  # If signup failed (user exists), try signin
  if [ -z "${jwt_token:-}" ]; then
    local signin_response
    signin_response=$(curl -sf -X POST "${NOCODB_URL}/api/v1/auth/user/signin" \
      -H "Content-Type: application/json" \
      --data-raw "$auth_payload" 2>/dev/null) || true

    jwt_token=$(echo "${signin_response:-}" | jq -r '.token // empty' 2>/dev/null) || jwt_token=""
    if [ -n "$jwt_token" ]; then
      info "  Signed in as existing admin."
    else
      warn "  Could not authenticate to NocoDB. Token creation deferred."
      return 0
    fi
  fi

  # Create persistent API token
  local token_response
  # Try v2 endpoint first, fall back to v1
  token_response=$(curl -sf -X POST "${NOCODB_URL}/api/v1/tokens" \
    -H "xc-auth: ${jwt_token}" \
    -H "Content-Type: application/json" \
    -d '{"description":"nemoclaw-agent"}' 2>/dev/null) || true

  if [ -z "$token_response" ]; then
    # Fallback: try meta endpoint
    token_response=$(curl -sf -X POST "${NOCODB_URL}/api/v1/meta/api-tokens" \
      -H "xc-auth: ${jwt_token}" \
      -H "Content-Type: application/json" \
      -d '{"description":"nemoclaw-agent"}' 2>/dev/null) || true
  fi

  api_token=$(echo "${token_response:-}" | jq -r '.token // empty' 2>/dev/null) || api_token=""

  if [ -n "$api_token" ]; then
    put_secret "$SECRETS_DIR" nocodb_api_token "$api_token"
    info "  API token created and saved."
  else
    warn "  API token creation failed — may need manual creation."
  fi
}

# ── Step 4: Store token in OpenBao ────────────────────────────────────────────

step_store_in_openbao() {
  info "Step 4: Storing NocoDB token in OpenBao..."
  store_token_in_openbao "$SECRETS_DIR" nocodb_api_token "services/nocodb" api_token
}

# ── Step 5: Validate ──────────────────────────────────────────────────────────

step_validate() {
  info "Step 5: Validating NocoDB deployment..."
  local api_token
  api_token=$(get_secret "$SECRETS_DIR" nocodb_api_token)

  check_http "${NOCODB_URL}/api/v1/health" "Health"

  if ! needs_gen "$api_token"; then
    check_http "${NOCODB_URL}/api/v1/auth/user/me" "API token" "xc-token" "$api_token"
  else
    warn "  API token: not yet created"
  fi
}

# ── Main ──────────────────────────────────────────────────────────────────────

main() {
  info "=== NocoDB Deployment ==="
  detect_runtime

  step_generate_secrets
  step_start_services
  step_bootstrap_credentials
  step_store_in_openbao
  step_validate

  info "=== NocoDB deployment complete ==="
}

main "$@"
