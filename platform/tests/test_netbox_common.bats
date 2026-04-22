#!/usr/bin/env bats
# Tests for platform/services/netbox/deployment/lib/common.sh pure functions.
# Run: bats platform/tests/test_netbox_common.bats

setup() {
  export SCRIPT_DIR="$BATS_TEST_DIRNAME/../services/netbox/deployment"
  export SECRETS_DIR=$(mktemp -d)
  export ENV_DIR=$(mktemp -d)
  export DOT_ENV=$(mktemp)
  export DEFAULT_TIMEOUT=10
  export CONTAINER_ENGINE="docker"
  export CONTAINER_SEP="-"
  export LIB_DIR="$SCRIPT_DIR/lib"
  TEST_DIR=$(mktemp -d)

  _COMMON_SH_LOADED=""
  source "$SCRIPT_DIR/lib/common.sh"
}

teardown() {
  rm -rf "$TEST_DIR" "$SECRETS_DIR" "$ENV_DIR" "$DOT_ENV"
}

# ── gen_secret ──────────────────────────────────────────────────────

@test "netbox gen_secret produces at least 20 chars by default" {
  result=$(gen_secret)
  [ ${#result} -ge 20 ]
}

@test "netbox gen_secret produces alphanumeric output" {
  result=$(gen_secret)
  [[ ! "$result" =~ [/+=] ]]
}

# ── gen_django_key ──────────────────────────────────────────────────

@test "gen_django_key produces 64 chars" {
  result=$(gen_django_key)
  [ ${#result} -eq 64 ]
}

@test "gen_django_key contains special characters" {
  result=$(gen_django_key)
  [[ "$result" =~ [!@#\$%\^] ]]
}

# ── get_secret / put_secret ─────────────────────────────────────────

@test "netbox put_secret creates file" {
  put_secret "db_pass" "my_secret"
  [ -f "$SECRETS_DIR/db_pass.txt" ]
}

@test "netbox put_secret sets restricted permissions" {
  put_secret "db_pass" "my_secret"
  perms=$(stat -f "%Lp" "$SECRETS_DIR/db_pass.txt" 2>/dev/null || stat -c "%a" "$SECRETS_DIR/db_pass.txt" 2>/dev/null)
  [ "$perms" = "600" ]
}

@test "netbox get_secret reads value" {
  put_secret "db_pass" "my_secret"
  result=$(get_secret "db_pass")
  [ "$result" = "my_secret" ]
}

@test "netbox get_secret returns empty for missing" {
  result=$(get_secret "nonexistent")
  [ -z "$result" ]
}

# ── needs_gen ───────────────────────────────────────────────────────

@test "netbox needs_gen true for empty" {
  needs_gen ""
}

@test "netbox needs_gen true for CHANGE_ME prefix" {
  needs_gen "CHANGE_ME_LATER"
}

@test "netbox needs_gen true for placeholder prefix" {
  needs_gen "placeholder_value"
}

@test "netbox needs_gen false for real value" {
  ! needs_gen "actual_password_123"
}

# ── get_val ─────────────────────────────────────────────────────────

@test "get_val extracts value from env file" {
  echo "MY_VAR=hello_world" > "$TEST_DIR/test.env"
  result=$(get_val "$TEST_DIR/test.env" "MY_VAR")
  [ "$result" = "hello_world" ]
}

@test "get_val handles quoted values" {
  echo "MY_VAR='quoted_value'" > "$TEST_DIR/test.env"
  result=$(get_val "$TEST_DIR/test.env" "MY_VAR")
  [ "$result" = "quoted_value" ]
}

@test "get_val returns empty for missing key" {
  echo "OTHER_VAR=value" > "$TEST_DIR/test.env"
  result=$(get_val "$TEST_DIR/test.env" "MY_VAR")
  [ -z "$result" ]
}

# ── read_existing ───────────────────────────────────────────────────

@test "read_existing prefers secrets dir over env file" {
  put_secret "test_val" "from_secrets"
  echo "TEST_VAR=from_env" > "$TEST_DIR/test.env"
  result=$(read_existing "test_val" "$TEST_DIR/test.env" "TEST_VAR")
  [ "$result" = "from_secrets" ]
}

@test "read_existing falls back to env file" {
  echo "TEST_VAR=from_env" > "$TEST_DIR/test.env"
  result=$(read_existing "missing_secret" "$TEST_DIR/test.env" "TEST_VAR")
  [ "$result" = "from_env" ]
}

@test "read_existing returns empty when both missing" {
  result=$(read_existing "missing" "$TEST_DIR/nonexistent.env" "MISSING_VAR")
  [ -z "$result" ]
}
