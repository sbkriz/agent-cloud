# Branch Testing Workflow

**Date:** 2026-04-22
**Status:** ACTIVE

---

## Overview

All deploy playbooks support a `service_branch` variable (defaults to `main`). This enables deploying feature branches to production infrastructure for validation before merging, with instant rollback by re-deploying from main.

## Workflow

```text
1. Develop          Push feature branch to GitHub
                                │
2. Deploy branch    Semaphore deploy template → set Branch = "feat/my-feature"
                    (git clones the branch on the target VM, deploys from it)
                                │
3. Validate         Run validation templates (Check Discovery, Validate All, etc.)
                    Confirm expected behavior, check for errors
                                │
                    ┌──── PASS ────┐          ┌──── FAIL ────┐
                    │              │          │               │
4a. Create PR    gh pr create   4b. Rollback   Re-run deploy template
    Wait checks  CodeRabbit etc     │          with Branch = "" (defaults to main)
    Fix findings                    │          Fix code on branch, retry step 2
    All pass                        │
    Merge PR                        │
                    │               │
5. Deploy main   Re-run deploy template with Branch = "" (defaults to main)
                 Confirms merged code works in production
```

## How It Works

### Playbook Support

Every deploy playbook reads `service_branch` with a fallback to `main`:

```yaml
# deploy-orb-agent.yml
- name: "Update monorepo to latest"
  ansible.builtin.git:
    repo: "{{ monorepo_repo }}"
    dest: "{{ _monorepo_dir }}"
    version: "{{ service_branch | default('main') }}"
    force: true
```

Playbooks with `service_branch` support:
- `deploy-all.yml`
- `deploy-openbao.yml`
- `deploy-nocodb.yml`
- `deploy-n8n.yml`
- `deploy-semaphore.yml`
- `deploy-netbox.yml`
- `deploy-nemoclaw.yml`
- `clean-deploy-netbox.yml`
- `deploy-orb-agent.yml`

### Semaphore Survey Variables

All deploy templates include a `survey_vars` field for `service_branch`. In the Semaphore UI, this appears as a "Branch" text field when launching a task. Leave it empty to deploy from main.

```yaml
# platform/semaphore/templates.yml
- name: Deploy Orb Agent
  playbook: platform/playbooks/deploy-orb-agent.yml
  survey_vars:
    - name: service_branch
      title: "Branch"
      description: "Git branch to deploy (default: main)"
      type: string
      required: false
```

### API Usage

Deploy a specific branch via the Semaphore API:

```bash
curl -X POST -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{
    "template_id": 47,
    "project_id": 1,
    "environment": "{\"service_branch\": \"feat/my-feature\"}"
  }' \
  "http://$SEMAPHORE_HOST:3000/api/project/1/tasks"
```

Deploy from main (rollback or post-merge deploy):

```bash
curl -X POST -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{"template_id": 47, "project_id": 1}' \
  "http://$SEMAPHORE_HOST:3000/api/project/1/tasks"
```

## Safety Properties

1. **Non-destructive**: The branch deploy only changes the code on the target VM. It does not modify OpenBao secrets, database state, or persistent volumes.
2. **Instant rollback**: Re-running the deploy template without `service_branch` reverts to main within ~60 seconds.
3. **No merge required**: Branch code can be validated in production without touching main. If it fails, rollback and fix.
4. **Composable with validation**: After deploying a branch, run any validation template (Check Discovery, Validate All, Validate Secrets) to confirm the change works.

## Validation Templates

| Template | Purpose | When to Use |
| -------- | ------- | ----------- |
| Check Discovery Pipeline | Entity counts, worker logs, VMs, Clusters, primary_ip4 | After deploying worker code changes |
| Validate All Services | HTTP health checks on all services | After any service deploy |
| Validate Secrets | Test credentials against live services | After secret or AppRole changes |
| Cleanup NetBox (dry_run) | Check for orphaned entities | After entity model changes |

## PR Merge Rules

After branch validation succeeds:

1. Create a PR via `gh pr create`
2. Wait for **all PR checks** to complete (CodeRabbit, CI, linters)
3. Address all review findings and push fixes
4. Confirm all checks pass after fixes
5. Merge the PR
6. Re-deploy from main to confirm the merge is clean

**Never merge a PR before its checks have completed and passed.**
