# Linting and Testing Guide

This guide covers the automated quality gates that run on every pull request to main.

---

## CI Pipeline

Every PR triggers two GitHub Actions jobs:

### Static Analysis

| Tool | What it checks | Config file | Scope |
| ---- | -------------- | ----------- | ----- |
| **Ruff** | Python lint (style, imports, bugs) | `pyproject.toml` | All `.py` files |
| **ShellCheck** | Bash lint (quoting, unused vars, bugs) | Built-in rules | All `.sh` files (excludes `netbox-docker/`) |
| **ansible-lint** | Ansible playbook lint (syntax, best practices) | `.ansible-lint` | `platform/playbooks/` |
| **yamllint** | YAML lint (syntax, trailing spaces, newlines) | `.yamllint.yml` | All `.yml`/`.yaml` files (excludes `netbox-docker/`) |
| **hadolint** | Dockerfile lint (base images, layers, security) | Built-in rules | Custom Dockerfiles (excludes vendored) |

### Security Scan

| Tool | What it checks | Scope |
| ---- | -------------- | ----- |
| **TruffleHog** | Verified secrets (API keys, tokens, passwords) | Full repo history |
| **IP/credential grep** | Leaked IPs (`192.168.*`) and credential patterns | PR diff only |

---

## Running Locally

### Python (Ruff)

```bash
pip install ruff
ruff check .                    # Check all Python files
ruff check --fix .              # Auto-fix safe issues
ruff check --fix --unsafe-fixes .  # Fix all (review changes)
```

Configuration is in `pyproject.toml` under `[tool.ruff]`.

### Bash (ShellCheck)

```bash
# macOS
brew install shellcheck

# Ubuntu
apt install shellcheck

# Check all scripts (excludes netbox-docker/)
find . -name '*.sh' ! -path '*/netbox-docker/*' -exec shellcheck -S warning {} +
```

### Ansible (ansible-lint)

```bash
pip install ansible-lint
ansible-lint platform/playbooks/
```

Configuration is in `.ansible-lint`. Skips `command-instead-of-module` and `no-changed-when` (intentional patterns in deploy playbooks).

### YAML (yamllint)

```bash
pip install yamllint
yamllint -c .yamllint.yml .
```

### Dockerfiles (hadolint)

```bash
# macOS
brew install hadolint

# Check custom Dockerfile
hadolint platform/services/netbox/deployment/Dockerfile-Plugins
```

### Secret Scanning (TruffleHog)

```bash
# Install
brew install trufflehog  # or: pip install trufflehog

# Scan current branch
trufflehog git file://. --only-verified --branch HEAD
```

---

## Rules and Exceptions

### Ruff (Python)

**Selected rules:** E (errors), F (pyflakes), W (warnings), I (imports), UP (pyupgrade), B (bugbear), SIM (simplify), PIE (misc), C4 (comprehensions), BLE (blind except).

**Intentionally ignored:**

| Rule | Reason |
| ---- | ------ |
| BLE001 | Blind `except Exception` is intentional in worker error handling — workers must not crash the orb-agent |
| SIM105 | `try-except-pass` is clearer than `contextlib.suppress` for inline type coercion |
| C408 | `dict(key=value)` calls are preferred over `{"key": value}` for readability with many keyword args |

**Per-file overrides:** `platform/services/netbox/deployment/lib/pfsense-sync.py` allows E501 (long lines) because it's a legacy standalone script.

### ShellCheck (Bash)

Severity is set to **warning** — both errors and warnings fail CI.

Common fixes:

| Code | Issue | Fix |
| ---- | ----- | --- |
| SC2064 | Trap uses double quotes (expands now) | Use single quotes: `trap 'cleanup' EXIT` |
| SC2034 | Variable appears unused | Remove it, export it, or prefix with `_` |
| SC2086 | Unquoted variable | Quote it: `"$VAR"` |
| SC2155 | Declare and assign separately | Split: `local x; x=$(cmd)` |

### yamllint (YAML)

Uses the `relaxed` base with:
- Line length: 200 characters max
- Trailing spaces: **enforced** (remove all trailing whitespace)
- Newline at end of file: **enforced**
- Truthy values: only `true`, `false`, `yes`, `no` allowed

---

## Adding a New Service

When onboarding a new service, your code must pass all CI checks before merge:

1. **Python code**: Run `ruff check` on any `.py` files. Fix import ordering, unused imports, and f-string issues before pushing.
2. **Shell scripts**: Run `shellcheck -S warning` on your `deploy.sh`. Quote variables, use single-quoted traps, remove unused vars.
3. **Ansible playbooks**: Run `ansible-lint` on new or modified playbooks.
4. **YAML files**: Run `yamllint -c .yamllint.yml` on compose files, playbooks, and templates. Remove trailing spaces, ensure final newline.
5. **Dockerfiles**: Run `hadolint` on custom Dockerfiles.
6. **Secrets**: Never commit real IPs, passwords, API tokens, or GPS coordinates. Use Jinja2 `{{ variable }}` references. Real values live in site-config (private repo).

### Pre-PR Checklist

```bash
# 1. Python lint
ruff check .

# 2. Shell lint
find . -name '*.sh' ! -path '*/netbox-docker/*' -exec shellcheck -S warning {} +

# 3. Ansible lint
ansible-lint platform/playbooks/

# 4. YAML lint
yamllint -c .yamllint.yml .

# 5. Dockerfile lint
hadolint platform/services/netbox/deployment/Dockerfile-Plugins

# 6. Secret scan
git diff --staged | grep -iE '^\+.*192\.168\.' | grep -v 'target\|host:\|subnet\|scope\|example'
git diff --staged | grep -iE '^\+.*password\s*[:=]\s*[A-Za-z0-9]{8}|^\+.*secret_id[:=]\s*[a-f0-9-]{30}'
```

---

## Test Framework (Phase 2 — planned)

Unit tests for discovery worker Python code will use **pytest** with mocked SDK dependencies. Configuration is in `pyproject.toml` under `[tool.pytest.ini_options]`. Tests will live in `platform/services/netbox/deployment/tests/`.

See `plan/architecture/TESTING-AND-LINTING-PLAN.md` for the full testing roadmap.
