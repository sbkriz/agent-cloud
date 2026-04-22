#!/usr/bin/env bats
# Tests for platform/services/netbox/deployment/lib/common.sh pure functions.

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

# ── gen_secret + gen_django_key ─────────────────────────────────────

@test "gen_secret: alphanumeric, >= 20 chars" {
  result=$(gen_secret)
  [ ${#result} -ge 20 ]
  [[ ! "$result" =~ [/+=] ]]
}

@test "gen_django_key: 64 chars with special characters" {
  result=$(gen_django_key)
  [ ${#result} -eq 64 ]
  [[ "$result" =~ [!@#\$%\^] ]]
}

# ── get_secret / put_secret ─────────────────────────────────────────

@test "put/get_secret: create, read, permissions, missing" {
  put_secret "db_pass" "my_secret"
  [ -f "$SECRETS_DIR/db_pass.txt" ]
  [ "$(get_secret "db_pass")" = "my_secret" ]

  # Cross-platform permission check (macOS vs Linux stat)
  if stat -f "%Lp" "$SECRETS_DIR/db_pass.txt" >/dev/null 2>&1; then
    perms=$(stat -f "%Lp" "$SECRETS_DIR/db_pass.txt")
  else
    perms=$(stat -c "%a" "$SECRETS_DIR/db_pass.txt")
  fi
  [ "$perms" = "600" ]

  [ -z "$(get_secret "nonexistent")" ]
}

# ── needs_gen ───────────────────────────────────────────────────────

@test "needs_gen: true for empty/placeholder, false for real values" {
  needs_gen ""
  needs_gen "CHANGE_ME_LATER"
  needs_gen "placeholder_value"
  ! needs_gen "actual_password_123"
}

# ── get_val ─────────────────────────────────────────────────────────

@test "get_val: extracts values, handles quotes, returns empty for missing" {
  echo "MY_VAR=hello_world" > "$TEST_DIR/test.env"
  echo "QUOTED='quoted_value'" >> "$TEST_DIR/test.env"

  [ "$(get_val "$TEST_DIR/test.env" "MY_VAR")" = "hello_world" ]
  [ "$(get_val "$TEST_DIR/test.env" "QUOTED")" = "quoted_value" ]
  [ -z "$(get_val "$TEST_DIR/test.env" "MISSING")" ]
}

# ── read_existing ───────────────────────────────────────────────────

@test "read_existing: prefers secrets, falls back to env, empty when both missing" {
  put_secret "test_val" "from_secrets"
  echo "TEST_VAR=from_env" > "$TEST_DIR/test.env"

  [ "$(read_existing "test_val" "$TEST_DIR/test.env" "TEST_VAR")" = "from_secrets" ]
  [ "$(read_existing "missing" "$TEST_DIR/test.env" "TEST_VAR")" = "from_env" ]
  [ -z "$(read_existing "missing" "$TEST_DIR/none.env" "MISSING")" ]
}
