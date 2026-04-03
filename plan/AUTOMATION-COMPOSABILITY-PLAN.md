# Automation Composability Plan

**Date:** 2026-04-02
**Status:** ACCEPTED — Implementing with NetBox as first service
**Context:** The NetBox deployment exposed that deploy.sh scripts mix infrastructure concerns (credential management, OpenBao) with container operations (compose, migrations). This plan decomposes service deployments into reusable Ansible building blocks that Semaphore orchestrates.

---

## Problem

Each service's deploy.sh is a monolith that handles everything from secret generation to container lifecycle to API bootstrapping. This creates:

1. **Secret drift** — deploy.sh generates new secrets on each run if intermediary files are missing, causing password mismatches with existing databases
2. **Duplication** — Every deploy.sh reimplements OpenBao auth, secret generation, health waiting
3. **Tight coupling** — deploy.sh needs OpenBao credentials but Ansible already has them natively
4. **No validation** — Secrets are generated and used without verifying they work
5. **Intermediary files** — secrets/ directory on VM is a redundant copy of what's in OpenBao

## Solution: OpenBao-Driven Secret Lifecycle

**OpenBao is the single source of truth.** No secrets/ directory on VMs. Ansible fetches from OpenBao, templates compose-ready config files directly, and deploy.sh only runs container operations.

### Architecture

```
OpenBao (source of truth)
  ↑ generate + store (first deploy)
  ↓ fetch (all deploys)
Ansible (manage-secrets.yml)
  ↓ template
env/*.env, .env, config files (on VM, compose-ready)
  ↓ read
deploy.sh (container operations: compose up, migrations, health)
```

### Secret Lifecycle

**First deploy (no secrets in OpenBao):**
1. `manage-secrets.yml` checks OpenBao — empty
2. Generates random secrets via Ansible `password` lookup
3. Stores all secrets in OpenBao
4. Templates env files on VM from generated values
5. deploy.sh starts containers using the env files

**Subsequent deploys (secrets exist in OpenBao):**
1. `manage-secrets.yml` checks OpenBao — has values
2. Reuses all existing secrets (no regeneration)
3. Templates env files on VM from fetched values
4. deploy.sh starts containers — passwords match existing database volumes

**Secret validation (check-secrets.yml):**
1. Reads secrets from OpenBao
2. Tests each credential against its service (DB connect, API call, HTTP auth)
3. Reports which secrets are valid, expired, or missing
4. Does NOT modify anything — read-only verification

---

## Composable Task Library

```
platform/playbooks/tasks/
  manage-secrets.yml       Fetch/generate secrets via OpenBao, template env files  [IMPLEMENTED]
  clone-and-deploy.yml     Clone monorepo, run deploy.sh, health check             [IMPLEMENTED]
  clean-service.yml        Destroy containers, volumes, clone (full wipe)           [IMPLEMENTED]
  clone-repo.yml           Clone/update monorepo on target VM                      [PLANNED]
  run-deploy.yml           Execute deploy.sh (container operations only)            [PLANNED]
  verify-health.yml        Health check a service endpoint                          [PLANNED]

platform/playbooks/
  deploy-<service>.yml     Composable: clone + secrets + deploy + verify            [NETBOX DONE]
  clean-deploy-<service>.yml  Wipe + fresh deploy                                  [NETBOX DONE]
  check-secrets.yml        Read-only secret inventory from OpenBao                  [IMPLEMENTED]
  validate-secrets.yml     Active credential testing (DB, Redis, HTTP)              [IMPLEMENTED]
  distribute-ssh-keys.yml  Deploy SSH keys from OpenBao                             [IMPLEMENTED]
  harden-ssh.yml           NOPASSWD sudo + sshd lockdown                            [IMPLEMENTED]
  install-docker.yml       Install Docker CE (standalone)                            [IMPLEMENTED]
  sync-secrets-to-openbao.yml  Push VM secrets → OpenBao (recovery/migration)       [IMPLEMENTED]
```

### Task Responsibilities

**`clone-repo.yml`**
- Clone or update `~/agent-cloud` via HTTPS (public repo, no creds)
- Create convenience symlink `~/<service>`
- No credentials needed

**`manage-secrets.yml`**
- Authenticate to OpenBao via AppRole
- Fetch existing secrets from `secret/services/<service_name>`
- Generate missing secrets (random or Django-style, per `_secret_definitions`)
- Store all secrets (existing + generated) back to OpenBao
- Template service-specific env files (`env/*.env`, `.env`, config files)
- Accepts `_secret_definitions` list: `[{name, type, length}]`
  - `type: random` — generated if missing (passwords, tokens)
  - `type: django` — Django secret key format if missing
  - `type: user` — user-managed, never auto-generated (SNMP, API keys)
- Accepts `_env_templates` list of Jinja2 templates to render

**`run-deploy.yml`**
- `cd` to deployment dir, run `bash deploy.sh`
- Passes `CONTAINER_ENGINE` as env var
- deploy.sh verifies env files exist (but does NOT generate secrets)
- deploy.sh handles: upstream repos, image pull/build, compose lifecycle, migrations, superuser, OAuth2, agent start

**`verify-health.yml`**
- HTTP GET to `service_url + health_path`
- Retries with backoff
- Reports HEALTHY/UNHEALTHY

**`clean-service.yml`**
- Finds and stops compose stack (detects docker-compose.yml or compose.yml)
- Destroys all volumes (`compose down -v`)
- Removes any leftover containers with service name prefix
- Removes the agent-cloud clone and convenience symlink
- Requires `become: true` for killing stale port processes
- Used by `clean-deploy-<service>.yml` before a fresh deploy

### Validation Playbooks

**`check-secrets.yml`** — Read-only secret inventory
- Lists all secrets in OpenBao for a service
- Reports which are present, which are missing, which are empty
- Does NOT generate or modify anything
- Usage: pre-deploy check, audit, troubleshooting

**`validate-secrets.yml`** — Active credential testing
- Fetches secrets from OpenBao
- Tests each against its service:
  - DB passwords: `psql` connection test
  - API tokens: HTTP request with auth header
  - Redis passwords: `redis-cli ping` with auth
- Reports: valid, invalid, unreachable
- Does NOT modify anything — read-only verification
- Usage: post-deploy verification, scheduled health checks

---

## Composable Playbook Pattern

Every `deploy-<service>.yml` follows this structure:

```yaml
# Phase 1: Clone + Secrets
- name: "Clone and manage secrets"
  hosts: <service>_svc
  tasks:
    - include_tasks: tasks/clone-repo.yml
    - include_tasks: tasks/manage-secrets.yml
      vars:
        _secret_definitions: [...]   # service-specific
        _env_templates: [...]        # service-specific

# Phase 2: Container Operations
- name: "Deploy containers"
  hosts: <service>_svc
  tasks:
    - include_tasks: tasks/run-deploy.yml

# Phase 3: Verify
- name: "Verify deployment"
  hosts: <service>_svc
  tasks:
    - include_tasks: tasks/verify-health.yml
```

Services that need Docker add `install-docker.yml` as a pre-phase. Services that need `become` for specific steps set it per-task.

---

## What deploy.sh Keeps vs What Moves to Ansible

| Concern | deploy.sh | Ansible |
|---------|-----------|---------|
| Clone upstream repos (e.g., netbox-docker) | Yes | No |
| Copy .example templates | Yes | No |
| **Generate secrets** | **No** | **Yes (manage-secrets.yml)** |
| **Write env files from secrets** | **No** | **Yes (Jinja2 templates)** |
| **OpenBao read/write** | **No** | **Yes (native hashi_vault)** |
| Pull/build container images | Yes | No |
| Start/stop compose services | Yes | No |
| Wait for container health | Yes | No |
| Run DB migrations | Yes | No |
| Create admin users | Yes | No |
| Register OAuth2 clients | Yes | No |
| Start privileged agents | Yes (sudo) | No |
| **Clone monorepo** | **No** | **Yes (clone-repo.yml)** |
| **Health check verification** | **No** | **Yes (verify-health.yml)** |
| **Docker/Podman installation** | **No** | **Yes (standalone playbook)** |
| **Secret validation** | **No** | **Yes (validate-secrets.yml)** |

### deploy.sh Becomes Pure Container Operations

```bash
#!/usr/bin/env bash
# deploy.sh — Container operations only.
# Secrets and env files managed by Ansible. Monorepo cloned by Ansible.

# Verify env files exist (Ansible must run first)
[ -f ".env" ] || error ".env missing. Deploy via Semaphore."
[ -f "env/netbox.env" ] || error "env/netbox.env missing."

step 1: clone upstream dependency repos
step 2: copy .example templates (non-secret config only)
step 3: verify env files present (fail if missing)
step 4: pull images
step 5: build custom images
step 6: stop stack
step 7: sync DB passwords (existing volumes)
step 8: start stack (staged)
step 9+: wait, migrate, create superuser, OAuth2, agent
```

No `generate-secrets.sh` call. No OpenBao code. No `BAO_ROLE_ID`. Pure container lifecycle.

---

## Env File Templates (Jinja2)

Each service provides Jinja2 templates that `manage-secrets.yml` renders:

```
platform/services/netbox/deployment/
  templates/
    netbox.env.j2
    postgres.env.j2
    discovery.env.j2
    dot-env.j2
    hydra.yaml.j2
```

These replace `generate-secrets.sh`'s env file writing logic. Variables come from the `_resolved_secrets` dict populated by `manage-secrets.yml`.

---

## Migration Path

1. **NetBox (current):** First service to implement full composable pattern
2. **Extract reusable tasks:** `clone-repo.yml`, `manage-secrets.yml`, `run-deploy.yml`, `verify-health.yml` from deploy-netbox.yml
3. **NocoDB + n8n:** Apply same pattern — define `_secret_definitions`, create env templates, simplify deploy.sh
4. **OpenBao:** Special case — bootstraps itself, but Ansible still manages post-deploy secret sync
5. **All future services:** Follow the composable pattern from day one

---

## Validation Criteria

| Check | Pass Condition |
|-------|---------------|
| No secrets/ directory on VM | deploy.sh reads from env files only |
| No generate-secrets.sh call | deploy.sh verifies, doesn't generate |
| OpenBao is authoritative | Redeploying reuses existing secrets |
| First deploy works | Empty OpenBao → generate → store → deploy |
| Subsequent deploy works | Existing OpenBao → fetch → template → deploy |
| check-secrets reports accurately | Lists all secrets, flags missing |
| validate-secrets tests credentials | DB/API/Redis auth verified |
| Task reuse works | Same manage-secrets.yml for netbox, nocodb, n8n |
| Idempotent end-to-end | Running deploy twice = same state |

## Security Considerations

- **No intermediary files:** Secrets go OpenBao → Ansible memory → env files. No `secrets/*.txt` on disk.
- **Env files are gitignored:** `.env` and `env/*.env` written by Ansible, never committed
- **Ansible `no_log: true`** on all secret-handling tasks
- **AppRole least privilege:** Semaphore's AppRole can read/write all service paths (orchestrator role)
- **Validation catches drift:** `validate-secrets.yml` detects when a password in OpenBao no longer matches the database
- **deploy.sh has no credential access:** Cannot authenticate to OpenBao, cannot generate secrets — reduces blast radius if compromised
