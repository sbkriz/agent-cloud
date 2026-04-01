# Playbooks

Ansible playbooks for deploying, updating, validating, and hardening agent-cloud services via Semaphore.

## Conventions

### Thin Wrappers

Each service has a `deploy-<service>.yml` and `update-<service>.yml` wrapper that imports the generic playbook with `target_service` set. This is required because the Semaphore version in use does not support `extra_cli_arguments` — variables must be set in the playbook or environment, not via CLI flags.

```yaml
# deploy-netbox.yml
- name: "Deploy NetBox"
  import_playbook: deploy-service.yml
  vars:
    target_service: netbox_svc
```

### Variable Sources

| Variable | Source | Notes |
|----------|--------|-------|
| `ansible_user` | Inventory (private) | No defaults in playbooks — must be set in inventory |
| `service_name` | Inventory per-host | e.g., `nocodb`, `openbao` |
| `monorepo_deploy_path` | Inventory per-host | Path within monorepo to deploy.sh |
| `monorepo_repo` | Inventory global | Git SSH URL |
| `openbao_addr` | Environment | OpenBao API URL |
| `bao_role_id` / `bao_secret_id` | Environment | AppRole credentials |
| `target_service` | Wrapper playbook vars | Inventory group name (e.g., `netbox_svc`) |

### Become (sudo)

`become` is **not** set in the inventory. Each playbook declares its own:
- `distribute-ssh-keys.yml` — `become: false` (writes to user-owned `~/.ssh/`)
- `harden-ssh.yml` — `become: true` (modifies `/etc/ssh/sshd_config`)
- `deploy-service.yml` — `become: false` (runs deploy.sh as the service user)
- `provision-vm.yml` — runs against Proxmox API, no SSH become

When a playbook needs become, pass `ansible_become_password` via a Semaphore environment if NOPASSWD sudo is not configured.

### Delegate Tasks

Tasks that run on the Semaphore runner (e.g., fetching keys from OpenBao, writing temp files) use `delegate_to: localhost` with explicit `become: false` — the runner container does not have sudo.

### Secrets

**No credentials, IPs, or usernames in playbooks.** All sensitive values come from:
- **Inventory** (private repo) — IPs, usernames, host vars
- **OpenBao** — SSH keys, API tokens, passwords (fetched at runtime via `community.hashi_vault`)
- **Semaphore environment** — AppRole credentials for OpenBao access

### SSH Keys

SSH keys are fetched from OpenBao at runtime and written to temp files that are cleaned up in `always` blocks. The pattern:

```yaml
- name: "Fetch key"
  set_fact:
    _key: "{{ lookup('community.hashi_vault.hashi_vault', 'secret/data/services/ssh:private_key', ...) }}"

- name: "Write to temp file"
  tempfile: { state: file }
  register: _key_file
  delegate_to: localhost

- name: "Set contents"
  copy: { content: "{{ _key }}\n", dest: "{{ _key_file.path }}", mode: "0600" }
  delegate_to: localhost
  no_log: true

# ... use _key_file.path ...

- name: "Cleanup"  # in always block
  file: { path: "{{ _key_file.path }}", state: absent }
  delegate_to: localhost
```

## Playbook Reference

### Deployment
| Playbook | Purpose |
|----------|---------|
| `deploy-service.yml` | Generic deploy: clone monorepo, run deploy.sh, health check |
| `deploy-all.yml` | Deploy all services in dependency order (4 phases) |
| `deploy-openbao.yml` | Deploy OpenBao |
| `deploy-nocodb.yml` | Deploy NocoDB |
| `deploy-n8n.yml` | Deploy n8n |
| `deploy-semaphore.yml` | Deploy Semaphore (new VM only) |
| `deploy-netbox.yml` | Deploy NetBox |
| `deploy-nemoclaw.yml` | Deploy NemoClaw |

### Updates
| Playbook | Purpose |
|----------|---------|
| `update-service.yml` | Generic update: pull images, restart compose, health check |
| `update-nocodb.yml` | Update NocoDB |
| `update-n8n.yml` | Update n8n |
| `update-semaphore.yml` | Update Semaphore |
| `update-netbox.yml` | Update NetBox |

### SSH & Security
| Playbook | Purpose |
|----------|---------|
| `distribute-ssh-keys.yml` | Deploy SSH keys from OpenBao, verify key auth (no sudo) |
| `harden-ssh.yml` | NOPASSWD sudo + sshd lockdown + post-lockdown verification (requires sudo) |

### Validation & Provisioning
| Playbook | Purpose |
|----------|---------|
| `validate-all.yml` | Health check all services (HTTP only, no SSH commands) |
| `provision-vm.yml` | Clone Proxmox template, configure cloud-init, provision VM |
| `provision-template.yml` | Create Proxmox VM template with cloud-init |
| `proxmox-validate.yml` | Validate Proxmox cluster readiness |

### Shared Tasks
| File | Purpose |
|------|---------|
| `tasks/clone-and-deploy.yml` | Reusable: clone monorepo, symlink, run deploy.sh, health check |

## Adding a New Service

1. Add the service to the inventory (private repo) under `agent_cloud` with `service_name` and `monorepo_deploy_path`
2. Create `platform/services/<service>/deployment/deploy.sh` (idempotent, sources `../../lib/common.sh`)
3. Create `deploy-<service>.yml` wrapper (import `deploy-service.yml` with `target_service: <service>_svc`)
4. Create `update-<service>.yml` wrapper (import `update-service.yml`)
5. Create Semaphore task templates pointing at the wrapper playbooks
6. Generate an SSH key pair, store in OpenBao at `secret/services/ssh/<service>`
7. Run `distribute-ssh-keys.yml` to deploy the key to the VM

## Dependencies

Declared in `collections/requirements.yml` (auto-installed by Semaphore):
- `community.hashi_vault` — OpenBao/Vault lookups
- `ansible.posix` — `authorized_key` module
