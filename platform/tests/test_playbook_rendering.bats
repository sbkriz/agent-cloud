#!/usr/bin/env bats
# Tests that Django shell commands in playbooks render valid Python.
# Catches Jinja2/f-string/heredoc conflicts before deployment.

setup() {
  PLAYBOOKS_DIR="$BATS_TEST_DIRNAME/../playbooks"
}

@test "cleanup-netbox: all heredocs are single-quoted and at least one exists" {
  local file="$PLAYBOOKS_DIR/cleanup-netbox.yml"
  [ -f "$file" ]

  # Unquoted heredocs let bash expand $vars inside Python f-strings
  ! grep -E "<<\s+PYSCRIPT\b" "$file"

  # At least one quoted heredoc exists
  grep -q "<< 'PYSCRIPT'" "$file"
}

@test "check-discovery: GPS fix uses shell module and avoids f-strings" {
  local file="$PLAYBOOKS_DIR/check-discovery.yml"
  [ -f "$file" ]

  # Must use ansible.builtin.shell (not command) to support heredoc/pipe
  grep -A2 "Fix GPS coordinates" "$file" | grep -q "ansible.builtin.shell"

  # f-strings with {var} conflict with Jinja2 {{ }} rendering
  local gps_section
  gps_section=$(sed -n '/Fix GPS coordinates/,/register:/p' "$file")
  ! echo "$gps_section" | grep -q "f'"
}
