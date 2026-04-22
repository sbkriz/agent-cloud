#!/usr/bin/env bats
# Tests for platform/lib/common.sh pure functions.
# Run: bats platform/tests/test_common.bats

setup() {
  # Source common.sh in a way that doesn't trigger error() exit on missing deps
  export CONTAINER_ENGINE="docker"
  export COMPOSE_CMD="docker compose"
  source "$BATS_TEST_DIRNAME/../lib/common.sh"
  TEST_DIR=$(mktemp -d)
}

teardown() {
  rm -rf "$TEST_DIR"
}

# ── gen_secret ──────────────────────────────────────────────────────

@test "gen_secret produces at least 20 chars by default" {
  result=$(gen_secret)
  [ ${#result} -ge 20 ]
}

@test "gen_secret produces requested length" {
  result=$(gen_secret 48 16)
  [ ${#result} -eq 16 ]
}

@test "gen_secret output is alphanumeric (no +/=)" {
  result=$(gen_secret)
  [[ ! "$result" =~ [/+=] ]]
}

@test "gen_secret produces different values each call" {
  a=$(gen_secret)
  b=$(gen_secret)
  [ "$a" != "$b" ]
}

# ── needs_gen ───────────────────────────────────────────────────────

@test "needs_gen returns true for empty string" {
  needs_gen ""
}

@test "needs_gen returns true for REPLACE_ prefix" {
  needs_gen "REPLACE_ME"
}

@test "needs_gen returns true for changeme prefix" {
  needs_gen "changeme123"
}

@test "needs_gen returns true for placeholder prefix" {
  needs_gen "placeholder_value"
}

@test "needs_gen returns false for real value" {
  ! needs_gen "s3cur3_p4ssw0rd"
}

@test "needs_gen returns false for UUID" {
  ! needs_gen "550e8400-e29b-41d4-a716-446655440000"
}

# ── get_secret / put_secret ─────────────────────────────────────────

@test "put_secret creates file with correct value" {
  put_secret "$TEST_DIR" "test_key" "secret_value"
  [ "$(cat "$TEST_DIR/test_key.txt")" = "secret_value" ]
}

@test "put_secret creates file with restricted permissions" {
  put_secret "$TEST_DIR" "test_key" "secret_value"
  perms=$(stat -f "%Lp" "$TEST_DIR/test_key.txt" 2>/dev/null || stat -c "%a" "$TEST_DIR/test_key.txt" 2>/dev/null)
  [ "$perms" = "600" ]
}

@test "get_secret reads existing secret" {
  put_secret "$TEST_DIR" "test_key" "secret_value"
  result=$(get_secret "$TEST_DIR" "test_key")
  [ "$result" = "secret_value" ]
}

@test "get_secret returns empty for missing secret" {
  result=$(get_secret "$TEST_DIR" "nonexistent")
  [ -z "$result" ]
}

@test "put_secret overwrites existing value" {
  put_secret "$TEST_DIR" "test_key" "old_value"
  put_secret "$TEST_DIR" "test_key" "new_value"
  [ "$(cat "$TEST_DIR/test_key.txt")" = "new_value" ]
}

# ── detect_runtime ──────────────────────────────────────────────────

@test "detect_runtime respects CONTAINER_ENGINE if set" {
  export CONTAINER_ENGINE="podman"
  detect_runtime
  [ "$CONTAINER_ENGINE" = "podman" ]
}

# ── info/warn output ────────────────────────────────────────────────

@test "info outputs timestamped message" {
  result=$(info "test message")
  [[ "$result" =~ "test message" ]]
}

@test "warn outputs to stderr with WARN prefix" {
  run bash -c "source '${BATS_TEST_DIRNAME}/../lib/common.sh' && warn 'test warning' 2>&1 >/dev/null"
  [[ "$output" =~ "WARN" ]]
}
