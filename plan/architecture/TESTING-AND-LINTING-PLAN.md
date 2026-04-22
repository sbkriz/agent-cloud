# Testing and Linting Plan

**Date:** 2026-04-21
**Status:** IN PROGRESS — Phase 1 (static analysis) and Phase 5 (CI pipeline) implemented
**Contributors:** Architecture, Automation, Security, and Testing review agents

---

## Current State

The repository has **zero automated testing or linting infrastructure**. No GitHub Actions, no pre-commit hooks, no pytest, no shellcheck, no ansible-lint. The only quality gates are:

- A manual `grep`-based pre-push audit for leaked IPs/credentials (CLAUDE.md)
- Runtime validation playbooks in Semaphore (`validate-all.yml`, `validate-secrets.yml`, `check-discovery.yml`)
- CodeRabbit automated code review on PRs

## Guiding Principles

1. **Automate what's manual** — the pre-push audit grep patterns should be a pre-commit hook, not discipline
2. **Static analysis before unit tests** — linting catches more bugs per hour of setup than writing tests
3. **Test pure functions first** — the discovery workers have ~15 helper functions with clear contracts
4. **Don't test what Semaphore already validates** — runtime health checks against live services stay in Semaphore
5. **Security scanning is non-negotiable for a public repo** — gitleaks must gate every PR

---

## Phase 1: Static Analysis (immediate, no test infrastructure needed)

### 1a. Python Linting — Ruff

**Scope:** 3 Python modules (~1,700 LOC total)
- `workers/proxmox_discovery/proxmox_discovery/__init__.py`
- `workers/pfsense_sync/pfsense_sync/__init__.py`
- `lib/pfsense-sync.py`

**Configuration:** Add `[tool.ruff]` to root `pyproject.toml`:
```toml
[tool.ruff]
target-version = "py311"
line-length = 120

[tool.ruff.lint]
select = ["E", "F", "W", "I", "UP", "B", "SIM", "PIE", "C4", "BLE"]
ignore = ["BLE001"]  # blind except is intentional in worker error handling
```

### 1b. Shell Linting — ShellCheck

**Scope:** 26 shell scripts across the repo
- `platform/lib/common.sh`, `platform/lib/bao-client.sh`
- `platform/services/*/deployment/deploy.sh`
- `platform/services/netbox/deployment/lib/common.sh`, `lib/generate-secrets.sh`

**Tool:** `shellcheck` (install via `brew install shellcheck` or CI action)

### 1c. Ansible Linting

**Scope:** 50+ YAML playbooks and task files
- `platform/playbooks/*.yml`
- `platform/playbooks/tasks/*.yml`
- `platform/semaphore/templates.yml`

**Configuration:** `.ansible-lint` at repo root:
```yaml
skip_list:
  - command-instead-of-module  # deploy.sh invocations are intentional
  - no-changed-when            # many shell tasks are check commands
exclude_paths:
  - netbox-docker/
  - .github/
```

### 1d. YAML Linting

**Scope:** All YAML files (playbooks, compose files, agent configs, templates.yml)
**Tool:** `yamllint` with relaxed rules for Ansible compatibility

### 1e. Secret Scanning — gitleaks

**Scope:** All committed content + staged changes
**Tool:** `gitleaks` as pre-commit hook and CI gate
**Rationale:** The manual grep patterns in CLAUDE.md catch IPs and simple passwords but miss API tokens, SSH keys, base64 credentials, JWTs, PEM content. gitleaks covers all of these.

---

## Phase 2: Python Unit Tests

### Framework

**pytest** with a `conftest.py` providing shared fixtures and SDK mocks.

### Test Layout

```text
platform/services/netbox/deployment/
  tests/
    conftest.py                    # SDK stubs, mock factories
    test_proxmox_helpers.py        # Pure function tests
    test_proxmox_builders.py       # Entity builder tests (mocked SDK)
    test_pfsense_helpers.py        # _is_valid_ip, role validation
    test_pfsense_builders.py       # Entity builder tests (mocked SDK)
```

### Mock Strategy

The `worker.backend.Backend` and `worker.models` modules are orb-agent runtime-only — not pip-installable. Strategy:

1. Create stub modules in `conftest.py` via `sys.modules` injection
2. Install the real `netboxlabs-diode-sdk` as a test dependency (entity constructors are pure data containers)
3. Mock only `_reverse_dns()` (does DNS lookups) and any network calls

### Testable Functions — Pure Logic (no mocking needed)

| Function | Module | Est. Test Cases |
|----------|--------|----------------|
| `_int(val, default)` | proxmox_discovery | 6 |
| `_mb_to_gb(mb)` | proxmox_discovery | 4 |
| `_bytes_to_gb(b)` | proxmox_discovery | 4 |
| `_should_skip_iface(name)` | proxmox_discovery | 8 |
| `_iface_type(name)` | proxmox_discovery | 7 |
| `_prefix_len(cidr)` | proxmox_discovery | 5 |
| `_netmask_to_prefix(netmask)` | proxmox_discovery | 5 |
| `_sanitize_description(desc)` | proxmox_discovery | 8 |
| `_pick_primary_ipv4(ips)` | proxmox_discovery | 7 |
| `_is_valid_ip(addr_str)` | pfsense_sync | 8 |
| **Total** | | **~62** |

### Testable Functions — Mocked SDK/API

| Function | Mocks | Est. Test Cases |
|----------|-------|----------------|
| `_build_iface_entities()` | SDK ingester | 4 |
| `_build_vm_iface_entities()` | SDK ingester | 4 |
| `_build_node()` | ProxmoxAPI + SDK | 3 |
| `_build_vm()` | ProxmoxAPI + SDK | 4 |
| `_build_lxc()` | ProxmoxAPI + SDK | 3 |
| `_build_seed_entities()` | SDK ingester | 3 |
| `PfSenseSyncBackend._build_entities()` | PfSenseClient + SDK | 4 |
| **Total** | | **~25** |

### Coverage Targets

- Pure helpers: **90%+** (immediately achievable)
- Entity builders: **70-80%** (limited by mock complexity)
- Overall line coverage: **60%+** as initial target

---

## Phase 3: Bash Script Testing

### ShellCheck (static, Phase 1)

Already covered in Phase 1b.

### BATS Unit Tests (optional, medium effort)

**Scope:** `platform/lib/common.sh` functions that are pure enough to test:
- `gen_secret()` — random string generation
- `needs_gen()` — secret existence check logic
- `detect_runtime()` — container engine detection
- `sedi()` — cross-platform sed

**Framework:** [BATS](https://github.com/bats-core/bats-core) (Bash Automated Testing System)

---

## Phase 4: Security Testing

### 4a. Secret Scanning (Phase 1e)

Already covered. gitleaks as pre-commit + CI gate.

### 4b. Dependency Scanning

**Tool:** GitHub Dependabot or Renovate
**Scope:** Python deps in `pyproject.toml`, Ansible collections in `requirements.yml`, container images in `docker-compose.yml`

### 4c. Python Security Linting — Bandit

**Scope:** All Python files
**Integration:** Add to ruff or run standalone in CI
**Key checks:** hardcoded passwords, use of `exec`/`eval`, insecure deserialization

### 4d. Sanitization Regex Hardening

The `_sanitize_description()` regex covers `password|passwd|secret|token|key` but misses:
- `credential`, `apikey` (no underscore), `private`, `cert`, `bearer`, `auth`

Expand the pattern and add test cases. Balance false positives (stripping "keyboard" etc.) vs. credential leakage risk.

### 4e. TLS Verification Audit

Both `proxmox_discovery` and `pfsense_sync` default `verify_ssl=False`. Document this as an accepted risk for self-signed certs in homelab, but add a config option to enable verification when proper CA infrastructure exists.

---

## Phase 5: CI Pipeline (GitHub Actions)

### Proposed Workflow

```yaml
name: Lint and Test
on: [pull_request]

jobs:
  lint:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Python lint (ruff)
        uses: astral-sh/ruff-action@v3
      - name: Shell lint (shellcheck)
        uses: ludeeus/action-shellcheck@2.0.0
        with:
          scandir: platform/
      - name: Ansible lint
        run: pip install ansible-lint && ansible-lint platform/playbooks/
      - name: YAML lint
        run: pip install yamllint && yamllint -d relaxed .

  security:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Secret scan (gitleaks)
        uses: gitleaks/gitleaks-action@v2
      - name: IP/credential audit
        run: |
          ! git diff origin/main...HEAD | grep -iE '^\+.*192\.168\.' | grep -v 'target\|host:\|subnet\|scope\|example'
          ! git diff origin/main...HEAD | grep -iE '^\+.*password\s*[:=]\s*[A-Za-z0-9]{8}|^\+.*secret_id[:=]\s*[a-f0-9-]{30}'

  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
        with:
          python-version: "3.11"
      - name: Install test deps
        run: pip install pytest netboxlabs-diode-sdk
      - name: Run tests
        run: pytest platform/services/netbox/deployment/tests/ -v
```

### Semaphore Integration (unchanged)

Semaphore continues to own runtime validation:
- `validate-all.yml` — HTTP health checks
- `validate-secrets.yml` — credential testing against live services
- `check-discovery.yml` — entity count verification post-deploy

No changes needed to Semaphore. GitHub Actions handles pre-merge quality; Semaphore handles post-deploy verification.

---

## Implementation Priority

| Phase | Effort | Impact | Dependencies |
|-------|--------|--------|-------------|
| 1a. Ruff (Python lint) | Low | High | None |
| 1b. ShellCheck | Low | High | None |
| 1c. Ansible-lint | Low | Medium | None |
| 1e. gitleaks | Low | High | None |
| 5. GitHub Actions CI | Medium | High | Phases 1a-1e |
| 2. Python unit tests | Medium | High | pytest setup |
| 4b. Dependabot | Low | Medium | None |
| 1d. YAML lint | Low | Low | None |
| 3. BATS tests | Medium | Low | BATS setup |
| 4c. Bandit | Low | Medium | None |

**Recommended first commit:** Add `ruff` config to `pyproject.toml`, add `.ansible-lint`, add a GitHub Actions workflow with ruff + shellcheck + ansible-lint + gitleaks. This single PR establishes the quality gate for all future work.

---

## Challenges Identified by Review Team

1. **Orb-agent SDK not pip-installable** — `worker.backend.Backend` and `worker.models` are runtime-only. Tests must stub these via `sys.modules` in conftest.py.
2. **Shell scripts are platform-dependent** — `common.sh` detects Podman vs Docker at runtime. BATS tests need to mock or skip platform-specific paths.
3. **Ansible playbooks target live infrastructure** — Molecule would require extensive mocking. ansible-lint + `--check` mode are the pragmatic choices until a test environment exists.
4. **`_sanitize_description` false positive risk** — Expanding the keyword list risks stripping legitimate description content. Each new keyword needs negative test cases.
5. **TOCTOU in env file generation** — `generate_*_env()` functions in `common.sh` write files then chmod, leaving a brief window where secrets are world-readable. Fix: use `umask 077` subshells like `put_secret()` already does.
