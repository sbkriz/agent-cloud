# Semaphore orchestrator policy — read + write all service secrets
# Used by Semaphore playbooks to:
#   - Fetch credentials for SSH, Proxmox API, service tokens (read)
#   - Store deploy-generated secrets back to OpenBao (write)
# Semaphore is the deployment orchestrator — it needs write access
# to any service path because deploy.sh stores credentials during deployment.

path "secret/data/services/*" {
  capabilities = ["create", "read", "update", "patch", "list"]
}

path "secret/metadata/services/*" {
  capabilities = ["read", "list"]
}
