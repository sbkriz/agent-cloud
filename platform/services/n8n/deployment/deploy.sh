#!/usr/bin/env bash
# deploy.sh — Deploy n8n with programmatic owner setup + API key creation
# Idempotent: safe to re-run on an existing deployment.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$(dirname "$(dirname "$(dirname "$SCRIPT_DIR")")")/lib"
source "${LIB_DIR}/common.sh"
source "${LIB_DIR}/bao-client.sh"

SECRETS_DIR="${SCRIPT_DIR}/secrets"
CONFIG_DIR="${SCRIPT_DIR}/config"
N8N_URL="${N8N_URL:-http://localhost:5678}"
OPENBAO_ADDR="${OPENBAO_ADDR:-http://127.0.0.1:8200}"
ADMIN_EMAIL="${N8N_ADMIN_EMAIL:-admin@uhstray.io}"

# ── Step 1: Generate secrets & env file ───────────────────────────────────────

step_generate_secrets() {
  info "Step 1: Generating n8n secrets..."
  mkdir -p "$SECRETS_DIR"

  local admin_pass
  admin_pass=$(get_secret "$SECRETS_DIR" n8n_owner_password)
  needs_gen "$admin_pass" && admin_pass=$(gen_secret 16 32)
  put_secret "$SECRETS_DIR" n8n_owner_password "$admin_pass"

  generate_n8n_env "${CONFIG_DIR}/n8n.env" "$SECRETS_DIR"
}

# ── Step 2: Start services ────────────────────────────────────────────────────

step_start_services() {
  info "Step 2: Starting n8n services..."
  cd "$SCRIPT_DIR"
  compose up -d
  wait_for_http "${N8N_URL}/healthz" "n8n" 120
}

# ── Step 3: Bootstrap owner + API key ─────────────────────────────────────────

step_bootstrap_credentials() {
  info "Step 3: Bootstrapping n8n credentials..."
  local admin_pass api_key
  admin_pass=$(get_secret "$SECRETS_DIR" n8n_owner_password)

  api_key=$(get_secret "$SECRETS_DIR" n8n_api_key)
  if ! needs_gen "$api_key"; then
    info "  API key already exists — skipping bootstrap."
    return 0
  fi

  # Try owner setup (first boot only — fails if owner already exists)
  local setup_response setup_payload
  setup_payload=$(jq -n \
    --arg email "$ADMIN_EMAIL" \
    --arg pass "$admin_pass" \
    '{"email":$email,"firstName":"Admin","lastName":"User","password":$pass}')

  setup_response=$(curl -sf -X POST "${N8N_URL}/rest/owner/setup" \
    -H "Content-Type: application/json" \
    --data-raw "$setup_payload" 2>/dev/null) || true

  if [ -n "$setup_response" ]; then
    info "  Owner account created."
  else
    info "  Owner already exists — proceeding to login."
  fi

  # Login to get session cookie
  local cookie_jar login_payload
  cookie_jar=$(mktemp)
  trap "rm -f '$cookie_jar'" EXIT INT TERM

  login_payload=$(jq -n \
    --arg email "$ADMIN_EMAIL" \
    --arg pass "$admin_pass" \
    '{"emailOrLdapLoginId":$email,"password":$pass}')

  curl -sf -c "$cookie_jar" -X POST "${N8N_URL}/rest/login" \
    -H "Content-Type: application/json" \
    --data-raw "$login_payload" >/dev/null 2>&1 || {
    warn "  Login failed — API key creation deferred."
    return 0
  }
  info "  Logged in."

  # Create API key (scoped, no expiry)
  local key_response
  key_response=$(curl -sf -b "$cookie_jar" -X POST "${N8N_URL}/rest/api-keys" \
    -H "Content-Type: application/json" \
    -d '{"label":"nemoclaw-agent","scopes":["workflow:read","workflow:execute","workflow:list"],"expiresAt":0}' \
    2>/dev/null) || true

  api_key=$(echo "${key_response:-}" | jq -r '.data.rawApiKey // empty' 2>/dev/null) || api_key=""

  if [ -n "$api_key" ]; then
    put_secret "$SECRETS_DIR" n8n_api_key "$api_key"
    info "  API key created and saved."
    return 0
  fi

  # Fallback: direct DB insert (api_key is hex-only from openssl rand)
  info "  API endpoint unavailable — trying direct DB insert..."
  detect_runtime
  api_key=$(openssl rand -hex 20)
  # Validate api_key is hex-only to prevent injection
  if ! [[ "$api_key" =~ ^[0-9a-f]+$ ]]; then
    warn "  Generated key failed hex validation — aborting DB insert."
    return 0
  fi
  local insert_result
  insert_result=$($CONTAINER_ENGINE exec workflow-n8n-postgres \
    psql -U n8n_user -d n8n -t -A -c \
    "INSERT INTO api_key (user_id, label, api_key, created_at, updated_at)
     SELECT '1', 'nemoclaw-agent', '${api_key}', NOW(), NOW()
     WHERE NOT EXISTS (SELECT 1 FROM api_key WHERE label = 'nemoclaw-agent')
     RETURNING api_key;" 2>/dev/null) || insert_result=""

  if [ -n "$insert_result" ]; then
    put_secret "$SECRETS_DIR" n8n_api_key "$api_key"
    info "  API key created via DB insert."
  else
    warn "  API key creation failed — may need manual creation."
  fi
}

# ── Step 4: Store key in OpenBao ──────────────────────────────────────────────

step_store_in_openbao() {
  info "Step 4: Storing n8n API key in OpenBao..."
  store_token_in_openbao "$SECRETS_DIR" n8n_api_key "services/n8n" api_key
}

# ── Step 5: Validate ──────────────────────────────────────────────────────────

step_validate() {
  info "Step 5: Validating n8n deployment..."
  local api_key

  check_http "${N8N_URL}/healthz" "Health"

  api_key=$(get_secret "$SECRETS_DIR" n8n_api_key)
  if ! needs_gen "$api_key"; then
    check_http "${N8N_URL}/api/v1/workflows" "API key" "X-N8N-API-KEY" "$api_key"
  else
    warn "  API key: not yet created"
  fi
}

# ── Main ──────────────────────────────────────────────────────────────────────

main() {
  info "=== n8n Deployment ==="
  detect_runtime

  step_generate_secrets
  step_start_services
  step_bootstrap_credentials
  step_store_in_openbao
  step_validate

  info "=== n8n deployment complete ==="
}

main "$@"
