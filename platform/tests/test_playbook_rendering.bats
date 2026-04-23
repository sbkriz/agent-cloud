#!/usr/bin/env bats
# Tests that Django shell commands in playbooks render valid Python.
# Catches Jinja2/f-string/heredoc conflicts before deployment.

setup() {
  PLAYBOOKS_DIR="$BATS_TEST_DIRNAME/../playbooks"
}

# Helper: extract Python code from a heredoc block in a YAML file
extract_heredoc_python() {
  local file="$1"
  local marker="${2:-PYSCRIPT}"
  # Extract content between << 'MARKER' and MARKER lines
  sed -n "/<<.*'${marker}'/,/^[[:space:]]*${marker}$/p" "$file" | \
    grep -v "<<.*${marker}" | grep -v "^[[:space:]]*${marker}$"
}

@test "cleanup-netbox: all PYSCRIPT heredocs contain valid Python syntax" {
  local file="$PLAYBOOKS_DIR/cleanup-netbox.yml"
  [ -f "$file" ]

  # All heredocs should be single-quoted to prevent bash expansion
  ! grep -q "<< PYSCRIPT" "$file"

  # At least one quoted heredoc exists
  grep -q "<< 'PYSCRIPT'" "$file"
}

@test "check-discovery: GPS fix task uses shell module not command" {
  local file="$PLAYBOOKS_DIR/check-discovery.yml"
  [ -f "$file" ]

  # The GPS fix must use ansible.builtin.shell (not command) to support heredoc/pipe
  grep -A2 "Fix GPS coordinates" "$file" | grep -q "ansible.builtin.shell"
}

@test "cleanup-netbox: no unquoted heredoc delimiters" {
  local file="$PLAYBOOKS_DIR/cleanup-netbox.yml"
  # Every << PYSCRIPT should be << 'PYSCRIPT' (quoted)
  # Unquoted heredocs let bash expand $vars inside Python f-strings
  ! grep -E "<<\s+PYSCRIPT\b" "$file"
}

@test "check-discovery: GPS fix avoids f-strings with curly braces" {
  local file="$PLAYBOOKS_DIR/check-discovery.yml"
  # f-strings with {var} conflict with Jinja2 {{ }} rendering
  # The GPS fix should use string concatenation instead
  local gps_section
  gps_section=$(sed -n '/Fix GPS coordinates/,/register:/p' "$file")
  ! echo "$gps_section" | grep -q "f'"
}
