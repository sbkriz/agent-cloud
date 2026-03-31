# agent-cloud

Privacy-focused, open-source AI platform for startups and small business. Customizable, scalable, extensible, and performant.

**agent-cloud** is the unified platform monorepo — the single source of truth for "what we run and how." It consolidates service deployments, AI agent configurations, Ansible playbooks, Kubernetes manifests, and shared libraries into one repository.

## Architecture

agent-cloud follows a layered guardrails model where AI manages context and workloads, while automation tools execute outcomes behind policy enforcement:

```
┌─────────────────────────────────────────────────────┐
│                    AI Layer                         │
│  NemoClaw (workflow) + NetClaw (network) +          │
│  WisBot (community) + Claude Cowork (interactive)   │
│  Backed by: vLLM + llama.cpp (local LLM inference)  │
├─────────────────────────────────────────────────────┤
│                 Guardrail Layer                     │
│  OpenBao (secrets) · Kyverno (k8s) · OPA (policy)   │
│  Network policies · AppRole scoping · ITSM gating   │
│  AI proposes → guardrails validate → automation runs│
├─────────────────────────────────────────────────────┤
│               Automation Layer                      │
│  Ansible playbooks · Bash deploy scripts · Python   │
│  Deterministic, idempotent, auditable               │
├─────────────────────────────────────────────────────┤
│               Platform Layer                        │
│  Docker/Podman (dev) ↔ Kubernetes/OpenShift (prod)  │
│  Proxmox VMs (current) → k8s nodes (scale path)     │
└─────────────────────────────────────────────────────┘
```

### AI Agents

| Agent | Type | Role |
|-------|------|------|
| **NemoClaw** | Headless engineer | Background automation, API integrations, CI/CD, health monitoring. Runs in a sandboxed OpenShell runtime with policy-enforced security and OpenBao credential injection. |
| **NetClaw** | Network engineer | CCIE-level network monitoring, topology discovery, config backup, security auditing. 101+ skills with 46 MCP server backends. Separate network policy for direct device access. |
| **Claude Cowork** | Interactive architect | Research, architecture decisions, document generation, browser automation. Runs on personal devices with GUI capabilities. |
| **WisBot** | Community interface | Discord voice/chat bot with LLM-powered interactions, voice recording, reminders. C#/.NET, deployed as external dependency via A2A protocol. |

### Platform Services

| Service | Purpose |
|---------|---------|
| **OpenBao** | Secrets management — KV v2, AppRole auth, database engine. Single source of truth for all credentials. |
| **NocoDB** | Shared data layer — structured tables, REST API, task queue for cross-agent coordination. |
| **n8n** | Workflow automation — event-driven scheduling, webhooks, LLM nodes, queue-mode workers. |
| **Semaphore** | Deployment orchestration — Ansible playbook execution, infrastructure state management. |
| **NetBox** | Infrastructure modeling — IPAM/DCIM with Diode auto-discovery from network devices. |
| **Caddy** | Reverse proxy — automatic TLS, CloudFlare DNS integration. |
| **vLLM + llama.cpp** | Local LLM inference backbone — GPU-heavy and lightweight engines with OpenAI-compatible API. |

## Quick Start

```bash
# Clone the repo
git clone https://github.com/uhstray-io/agent-cloud.git
cd agent-cloud

# Deploy locally (compose-based, all services)
cd platform && ./orchestrate.sh --local

# Deploy a single service
cd platform/services/nocodb/deployment && ./deploy.sh
```

Every service follows the same 5-step deploy pattern: generate secrets → start containers → bootstrap credentials → store in OpenBao → validate. Learn one, know all.

## Repository Structure

```
agent-cloud/
├── platform/                          ← Infrastructure & service deployments
│   ├── services/                      ← Per-service: deployment/ + context/
│   │   ├── openbao/                   ← Secrets backbone
│   │   ├── nocodb/                    ← Data layer
│   │   ├── n8n/                       ← Workflow automation
│   │   ├── semaphore/                 ← Deployment orchestration
│   │   ├── netbox/                    ← Infrastructure modeling
│   │   ├── caddy/                     ← Reverse proxy
│   │   ├── inference/                 ← vLLM + llama.cpp
│   │   ├── o11y/                      ← Observability (Grafana/Prometheus/Loki/Tempo)
│   │   ├── a2a-registry/             ← Agent discovery service
│   │   ├── nextcloud/                 ← Cloud storage
│   │   ├── wikijs/                    ← Knowledge base
│   │   └── postiz/                    ← Content management
│   ├── lib/                           ← Shared libraries (common.sh, bao-client.sh)
│   ├── playbooks/                     ← Ansible playbooks (deploy, provision, validate)
│   ├── inventory/                     ← Inventory templates (no real IPs)
│   ├── hypervisor/proxmox/            ← VM provisioning and cloud-init
│   ├── k8s/                           ← Kubernetes manifests (Kustomize overlays)
│   │   ├── base/                      ← Generated from compose via kompose
│   │   ├── overlays/                  ← dev / staging / prod
│   │   └── bootstrap/                 ← k0s/kubeadm cluster setup
│   └── scripts/                       ← Setup and utility scripts
├── agents/                            ← AI agent configurations
│   ├── nemoclaw/                      ← Headless workflow agent
│   │   ├── deployment/                ← compose.yml, deploy.sh, sandbox config
│   │   └── context/                   ← skills, use-cases, prompts, architecture
│   ├── netclaw/                       ← Network engineering agent
│   │   ├── deployment/                ← compose.yml, testbed template, MCP config
│   │   └── context/                   ← network skills, pyATS templates
│   ├── cowork/                        ← Interactive architect agent context
│   └── workflows/                     ← n8n workflow exports and templates
├── data/                              ← Data warehouse, lake, analytics
│   ├── warehouse/                     ← PostgreSQL schemas and migrations
│   ├── lake/                          ← MinIO bucket configs and lifecycle rules
│   ├── analytics/                     ← DuckDB queries, Dagster assets
│   └── docs/                          ← Data dictionary, lineage diagrams
├── workstations/                      ← Developer device setup
├── CLAUDE.md                          ← AI agent guidance
└── README.md
```

Each service directory uses the **deployment/ + context/** split:
- **deployment/** — compose.yml, deploy.sh, .env.example, Dockerfile (how to run it)
- **context/** — skills, use-cases, prompts, architecture docs (how AI agents interact with it)

## Technology Stack

```
INFRASTRUCTURE        Docker/Podman · Kubernetes (k0s) · Proxmox · Harbor · Cilium
SECRETS & IDENTITY    OpenBao · Authentik (SSO/OIDC) · External Secrets Operator
DEPLOYMENT & GITOPS   Semaphore · ArgoCD · Kyverno · GitHub Actions
NETWORKING            Caddy · Traefik/Kong · NATS · NetBox
DATA                  PostgreSQL · MinIO · DuckDB · NocoDB · Superset · Qdrant
AI AGENTS             NemoClaw · NetClaw · Claude Cowork · WisBot
INFERENCE             vLLM (GPU) · llama.cpp (lightweight) · Hymba 1.5B (on-agent)
AGENT PROTOCOLS       A2A (agent↔agent) · MCP (agent↔tool) · NATS JetStream
OBSERVABILITY         Grafana · Prometheus · Loki · Tempo · OpenTelemetry
COLLABORATION         Nextcloud · Wiki.js · Postiz · Discord
```

## Credential Flow

All secrets are managed by OpenBao. Services authenticate via AppRole at runtime — no credentials are stored in environment files or committed to this repository:

```
Semaphore environment (AppRole role-id + secret-id only)
  → playbook starts
  → community.hashi_vault lookup
  → OpenBao AppRole auth → scoped token → fetch secrets
  → deploy.sh generates runtime env from OpenBao
  → compose up -d
```

## Related Repositories

| Repo | Visibility | Purpose |
|------|-----------|---------|
| [uhstray-io/agent-cloud](https://github.com/uhstray-io/agent-cloud) | Public | This repo — platform monorepo |
| [uhstray-io/NemoClaw](https://github.com/uhstray-io/NemoClaw) | Public | NVIDIA NemoClaw fork |
| [uhstray-io/WisBot](https://github.com/uhstray-io/WisBot) | Public | Discord bot (C#/.NET, external dependency) |
| [uhstray-io/WisAI](https://github.com/uhstray-io/WisAI) | Public | Personal LLM stack (Ollama + Open WebUI) |

## Contributing

- [Code of Conduct](https://www.uhstray.io/en/code-of-conduct)
- [CONTRIBUTING.md](CONTRIBUTING.md)
