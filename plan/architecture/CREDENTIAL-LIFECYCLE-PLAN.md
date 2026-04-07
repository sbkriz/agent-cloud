# Credential Lifecycle Management Plan

**Date:** 2026-04-05
**Status:** PROPOSED — Reviewed by security, network, infrastructure, automation, and architecture specialists
**Context:** Current credential management creates and accumulates without rotation, expiry, or cleanup. This plan establishes lifecycle management that scales from 1 site to 10+.

---

## Current Problems

1. **Credential accumulation** — Diode OAuth2 clients created every deploy, never deleted (no `delete_client` in plugin API)
2. **No expiry** — AppRole secret_ids have TTL=0, static KV secrets never expire
3. **No audit trail** — No tracking of creation time, creator, last use, or purpose
4. **No revocation workflow** — Decommissioned VMs leave orphaned credentials forever
5. **No multi-site path strategy** — `secret/services/*` has no mechanism for per-site isolation when scaling beyond one site
6. **Static database passwords** — Postgres credentials persist indefinitely (highest risk)

---

## Design Principles

1. **Every credential has a lifecycle:** created → active → verified → retired → deleted
2. **Every credential has metadata:** created_at, creator, site, purpose, expiry
3. **Verify before retiring:** new credential must pass validation before old is deleted
4. **Per-site isolation:** compromise of one site's credentials doesn't affect others
5. **OpenBao is the sole authority:** no credentials managed outside OpenBao
6. **Automation over manual:** rotation, cleanup, and auditing are scheduled playbooks

---

## Composable Vault Paths (Multi-Site Ready)

Rather than hardcoding a site hierarchy into OpenBao paths, the path structure is driven by a **`vault_secret_prefix`** inventory variable defined in **site-config**. This keeps agent-cloud site-agnostic and makes multi-site a configuration change, not a vault restructuring.

### How It Works

The `manage-secrets.yml` task constructs paths from the inventory variable:

```
secret/data/{{ vault_secret_prefix }}/{{ service_name }}
```

Site-config's inventory controls the prefix per site:

```yaml
# site-config/inventory/production.yml
agent_cloud:
  vars:
    vault_secret_prefix: "services"    # single-site (current)

# Future: site-config/inventory/remote-site.yml
remote_agent_cloud:
  vars:
    vault_secret_prefix: "sites/remote-dc/services"
```

### Single-Site Layout (Current)

With `vault_secret_prefix: "services"`, paths remain exactly as they are today:

```
secret/
  services/                            # vault_secret_prefix = "services"
    netbox                             # All NetBox secrets
    nocodb                             # NocoDB secrets
    n8n                                # n8n secrets
    ssh/management                     # Central SSH key
    ssh/<service>                      # Per-service SSH keys
    approles/semaphore                 # Platform orchestrator credentials
    approles/orb-agent                 # Orb-agent credentials
    discovery/
      pfsense                          # host, api_key
      snmp_v3                          # username, auth_password, priv_password
```

### Multi-Site Layout (Future)

When a second site is added, its inventory sets a site-scoped prefix:

```
secret/
  services/                            # vault_secret_prefix = "services" (original site)
    netbox
    nocodb
    ...

  sites/remote-dc/services/            # vault_secret_prefix = "sites/remote-dc/services"
    netbox                             # Remote site's NetBox secrets
    ssh/management                     # Remote site's SSH key
    approles/orb-agent                 # Remote site's orb-agent
    discovery/
      pfsense
      snmp_v3
```

### Why Not a Hardcoded Path Hierarchy

- **Site identity is a site-config concern** — embedding `uhstray-dc` into agent-cloud playbooks or vault paths leaks private topology into the public repo
- **No migration needed** — the current flat layout works as-is with `vault_secret_prefix: "services"`; multi-site is additive, not a restructure
- **Composable** — each site's inventory controls its own vault prefix; adding a site doesn't require changing agent-cloud code
- **AppRole policies follow the same pattern** — scoped to `{{ vault_secret_prefix }}/*` per site

### Migration Path

No dual-write migration is required. The current `secret/services/*` paths continue to work unchanged:

- **Now:** Add `vault_secret_prefix: "services"` to site-config inventory (matches existing layout)
- **When adding a second site:** Create a new inventory file with `vault_secret_prefix: "sites/<site_id>/services"` and provision that site's secrets under the new prefix
- **Original site stays untouched** — no path moves, no dual-write, no archive phase

---

## Credential Types & TTLs

| Credential Type | Current TTL | Proposed TTL | Rotation | Owner |
|----------------|------------|-------------|----------|-------|
| AppRole token | 30m | 30m (keep) | Auto-renew | OpenBao |
| AppRole secret_id | 0 (never) | **90 days** | Scheduled playbook | Ansible |
| AppRole token_num_uses | 0 (unlimited) | **25** | Per-token | OpenBao |
| Diode OAuth2 client | Never expires | **90 days** | Create→Verify→Retire | Ansible |
| Postgres password (static) | Never | **Migrate to dynamic** | On-demand (1h lease) | OpenBao DB engine |
| SSH keys | Never | 1 year | Annual rotation playbook | Ansible |
| SNMP community (v2c) | Never | Until SNMPv3 migration | — | Manual |
| SNMPv3 credentials | N/A | 180 days | Scheduled | Ansible |
| pfSense API key | Never | 180 days | Manual + store in OpenBao | Operator |
| OpenBao root token | Never rotated | **Rotate after setup** | One-time | Operator |

---

## Rotation Pattern: Create → Verify → Retire

All credential rotations follow this three-phase pattern:

```
Phase 1: CREATE
  → Generate new credential (Ansible/OpenBao)
  → Store in OpenBao with metadata (created_at, creator, purpose)
  → Mark as "pending_verification"

Phase 2: VERIFY
  → Test new credential against live service
  → If success: mark "active", proceed to Phase 3
  → If failure: STOP, alert operator, keep old credential active

Phase 3: RETIRE
  → Delete old credential from service (Hydra admin API, OpenBao revoke, etc.)
  → Archive old credential metadata (keep audit trail)
  → Update OpenBao: only "active" credential remains
```

**Critical rule:** Never delete the old credential before the new one is verified working. This is the "verify before hardening" principle applied to credentials.

---

## Diode Client Lifecycle

**Problem:** `netbox_diode_plugin.client` has `create_client()` and `list_clients()` but NO `delete_client()`.

**Solution:** Use Hydra admin API directly for deletion:

```bash
docker exec netbox-hydra-1 hydra admin clients delete <client_id>
```

**Rotation playbook: `rotate-diode-credentials.yml`**
1. List current clients via `list_clients()` in NetBox manage.py shell
2. Create new client via `create_client()`
3. Verify new client: `POST /diode/auth/oauth2/token` with new credentials
4. If verified: delete old clients via `hydra admin clients delete`
5. Store new credentials in OpenBao with `created_at` timestamp
6. Update `.env` on the VM

**Schedule:** Monthly, independent of deploy-orb-agent.yml

---

## Dynamic Database Secrets (Highest Impact)

**Current risk:** Static Postgres passwords live indefinitely. One compromised password exposes the entire database.

**Solution:** Configure OpenBao's database secrets engine for Postgres:

```hcl
# Configure database connection
resource "vault_database_secret_backend_connection" "netbox_pg" {
  backend       = "database"
  name          = "netbox-postgres"
  allowed_roles = ["netbox-app", "netbox-worker"]

  postgresql {
    connection_url = "postgresql://{{username}}:{{password}}@postgres:5432/netbox"
  }
}

# Role: short-lived app credentials
resource "vault_database_secret_backend_role" "netbox_app" {
  backend             = "database"
  name                = "netbox-app"
  db_name             = "netbox-postgres"
  creation_statements = ["CREATE ROLE \"{{name}}\" WITH LOGIN PASSWORD '{{password}}' VALID UNTIL '{{expiration}}'; GRANT ALL ON ALL TABLES IN SCHEMA public TO \"{{name}}\";"]
  default_ttl         = 3600   # 1 hour
  max_ttl             = 86400  # 24 hours
}
```

**Impact:** Services request fresh DB credentials on startup. Credentials auto-expire after 1 hour. No static passwords to compromise.

**Migration:** Phase 2 — after composable vault paths and credential metadata are in place. Requires compose changes to fetch credentials at container startup via entrypoint script.

---

## Audit & Monitoring

### OpenBao Audit Backend

Enable file audit logging:
```bash
bao audit enable file file_path=/openbao/audit/audit.log
```

Pipe to observability stack (Loki) for alerting on:
- Same secret read >10x in 1 minute (potential exfiltration)
- Secret access from unknown AppRole
- Failed authentication attempts

### Credential Inventory Playbook: `audit-credentials.yml`

Scheduled weekly via Semaphore (runs per-site via inventory targeting):
1. List all credentials under `{{ vault_secret_prefix }}` with creation dates
2. Compare against site-config inventory for expected services
3. List all Hydra OAuth2 clients with ages
4. List all AppRoles and their secret_id ages
5. Report: active, stale (>30 days unused), expired, orphaned
6. Flag credentials missing metadata

### Metadata on Every Secret

Every `manage-secrets.yml` call writes KV v2 custom metadata:
```json
{
  "created_at": "2026-04-05T12:00:00Z",
  "creator": "deploy-netbox.yml",
  "site": "uhstray-dc",
  "purpose": "NetBox Postgres password",
  "rotation_schedule": "dynamic-1h"
}
```

---

## Site Lifecycle

### Adding a New Site

1. Create site in NetBox (DCIM > Sites)
2. Add site inventory in **site-config** (new file or inventory group):
   - Define `vault_secret_prefix: "sites/<site_id>/services"` for the new site
   - Define host entries with `ansible_host`, `service_name`, `monorepo_deploy_path`
   - Set `openbao_addr` (central OpenBao or site-local instance)
3. Run `provision-site.yml` against the new inventory:
   - Creates site metadata in OpenBao at `{{ vault_secret_prefix }}/../metadata`
   - Generates SSH keys, stores at `{{ vault_secret_prefix }}/../ssh/`
   - Creates orb-agent AppRole scoped to `{{ vault_secret_prefix }}/*`
   - Discovers site core architecture (on-premise datacenter + VM, on-premise datacenter + kubernetes, cloud provider + kubernetes)
   - Provisions API and SNMP credentials based on discovered site architecture
4. Deploy services to the site using standard playbooks (paths resolve via inventory)

### Decommissioning a Site

1. Run `decommission-site.yml` against the site's inventory:
   - Mark site metadata status as `decommissioning`
   - Stop all services on site VMs
   - Revoke all AppRole secret_ids scoped to `{{ vault_secret_prefix }}`
   - Delete all Diode/Hydra clients for the site
   - Archive credentials (don't delete — keep audit trail for 90 days)
2. After 90 days: `archive-site.yml` deletes credential data permanently
3. Remove or archive the site's inventory file in site-config

---

## Implementation Phases

| Phase | What | Effort | Impact | Depends On |
|-------|------|--------|--------|------------|
| 1. Composable vault paths | Add `vault_secret_prefix` to site-config inventory, update `manage-secrets.yml` to use it | Low | Foundation for multi-site, no path migration needed | — |
| 2. Credential metadata | Add created_at/creator/site to manage-secrets.yml | Low | Audit visibility | Phase 1 |
| 3. AppRole TTL enforcement | secret_id_ttl=90d, token_num_uses=25 | Low | Limits blast radius | — |
| 4. Diode rotation playbook | Create→Verify→Retire with Hydra admin delete | Medium | Stops credential accumulation | Phase 2 |
| 5. Audit playbook + logging | audit-credentials.yml + OpenBao audit backend | Medium | Compliance, detection | Phase 2, o11y repository integrated into agent-cloud and Loki deployment |
| 6. Dynamic DB secrets | Configure database engine for Postgres | High | Eliminates static DB passwords | Phase 1 |
| 7. Site lifecycle playbooks | provision-site.yml, decommission-site.yml (site identity from site-config inventory) | Medium | Multi-site readiness | Phases 1-5 |

---

## Cross-Team Review Summary

| Reviewer | Key Finding |
|----------|------------|
| **Security** | secret_id TTL=0 is critical risk. 90-day lifecycle for Diode clients. Per-site AppRole isolation. |
| **Network** | Composable vault path prefix per site via inventory. Central OpenBao, path-based isolation via AppRole policies. |
| **Infrastructure** | Dynamic DB secrets highest impact. Token usage limits (num_uses=25). Audit backend to Loki. Namespaces overkill. |
| **Automation** | No delete_client in Diode plugin — use Hydra admin API. Create→Verify→Retire pattern. Monthly rotation schedule. |
| **Architecture** | Composable `vault_secret_prefix` driven from site-config inventory. KV v2 metadata for audit. No migration needed — current paths work as-is. NetBox Sites as credential registry. |
