---
name: ovh-dns
description: Safe OVH DNS management CLI — list, get, add, update, delete, backup, refresh DNS records via the OVH API
trigger: When the user asks to manage DNS records, check DNS, add/remove DNS entries, or anything related to OVH domain zone management
---

# ovh-dns

Safe CLI wrapper around the OVH API for DNS zone management.

## Usage

```
ovh-dns list <domain>                              # list all records
ovh-dns get <domain> <type> [name]                 # get records by type/name
ovh-dns add <domain> <type> <name> <value> [--ttl] # add a record
ovh-dns update <domain> <record-id> <value>        # update a record
ovh-dns delete <domain> <record-id> [--yes]        # delete (requires --yes)
ovh-dns backup <domain>                            # dump all records to JSON
ovh-dns refresh <domain>                           # apply pending changes
```

## Safety features

| Feature | Detail |
|---------|--------|
| **Scope lock** | Only `/domain/zone/*` API paths are permitted. All other OVH endpoints are blocked. |
| **Auto-backup** | Before any add/update/delete, the full zone is backed up to `~/fang/reports/dns-backups/<domain>-<timestamp>.json` |
| **Mutation log** | Every mutation is appended to `~/fang/reports/dns-mutations.jsonl` (timestamp, domain, action, old/new values) |
| **Delete guard** | `delete` requires `--yes` flag. Without it, shows what would be deleted and exits. |

## Config

Reads credentials from `~/fang/.ovh.conf` (INI format, python-ovh library).

## Examples

```bash
# List all DNS records for a domain
ovh-dns list elightstudios.fr

# Find all A records
ovh-dns get elightstudios.fr A

# Find CNAME for a specific subdomain
ovh-dns get elightstudios.fr CNAME www

# Add a new A record
ovh-dns add elightstudios.fr A staging 1.2.3.4 --ttl 3600

# Update an existing record
ovh-dns update elightstudios.fr 12345678 5.6.7.8

# Preview deletion (safe — no --yes)
ovh-dns delete elightstudios.fr 12345678

# Actually delete
ovh-dns delete elightstudios.fr 12345678 --yes

# Backup all records
ovh-dns backup elightstudios.fr

# Apply pending changes
ovh-dns refresh elightstudios.fr
```
