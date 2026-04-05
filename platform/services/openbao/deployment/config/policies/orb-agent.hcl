# orb-agent: read access to NetBox secrets and discovery credentials
# Used by the orb-agent's vault secrets manager to fetch Diode credentials,
# SNMP community strings, and pfSense API keys at runtime.

path "secret/data/services/netbox" {
  capabilities = ["read"]
}

path "secret/metadata/services/netbox" {
  capabilities = ["read"]
}

path "secret/data/services/discovery/*" {
  capabilities = ["read"]
}

path "secret/metadata/services/discovery/*" {
  capabilities = ["read"]
}

path "auth/token/renew-self" {
  capabilities = ["update"]
}
