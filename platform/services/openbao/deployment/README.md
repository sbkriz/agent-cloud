# OpenBao Deployment

OpenBao deployment code lives in the private `uhstray-io/openbao` repo (intentionally committed secrets for disaster recovery). The Ansible playbook `platform/playbooks/deploy-openbao.yml` clones that repo onto the target VM and runs its `deploy.sh`.

See [uhstray-io/openbao](https://github.com/uhstray-io/openbao) for compose.yml, deploy.sh, policies, and config.
