# Homelab OpenTofu

This directory provisions a small Proxmox homelab optimized for a single 16 GB laptop host:

- `lab-adguard` as a lightweight LXC for AdGuard Home
- `lab-edge` as a lightweight LXC for reverse proxy and browser-trusted local HTTPS
- `lab-docker` as a general-purpose VM for non-critical Docker Compose services
- `lab-jellyfin` as a lean LXC with optional host bind-mounted media storage

The checked-in defaults target the existing Proxmox node `norman` at `172.16.0.200` on `172.16.0.0/24`. The Proxmox host IP is managed outside this project and is not changed by Terraform.

## Prerequisites

- OpenTofu installed locally
- A Proxmox API token with permissions to create LXCs and, if enabled, VMs
- An LXC template already available in Proxmox storage
- A cloud-init capable VM template only if `enable_docker_host = true`
- A `.env` file exporting secret `TF_VAR_*` values plus `TF_VAR_ssh_public_key`

## Secrets

Create `.env` from `.env.example` and load it before running OpenTofu:

```sh
cp .env.example .env
cp terraform.tfvars.example terraform.tfvars
set -a
source .env
set +a
```

Provisioned guests are expected to be managed over SSH keys only. The same `TF_VAR_ssh_public_key` is injected into both service LXCs and VMs during provisioning.

## Usage

Update `terraform.tfvars` for your node name, storage names, template IDs, and static IPs, then run:

```sh
tofu init
tofu fmt
tofu validate
tofu plan
tofu apply
```

For the current `norman` host, the default managed guest addresses are:

- `lab-adguard`: `172.16.0.210`
- `lab-edge`: `172.16.0.211`
- `lab-jellyfin`: `172.16.0.230`
- `lab-docker`: disabled until `enable_docker_host = true` and `vm_template_id` is set

An existing unmanaged container named `adguard` may coexist with these resources. Terraform only manages guests present in its state.

## Service split

- `lab-adguard`: AdGuard Home only
- `lab-edge`: reverse proxy and browser-trusted wildcard HTTPS
- `lab-docker`: non-critical self-hosted apps
- `lab-jellyfin`: Jellyfin and a bind-mounted media path from the Proxmox host

For local-only HTTPS:

- AdGuard rewrites `*.lab.adre.me` to `lab-edge`
- Caddy in `lab-edge` serves `*.lab.adre.me` with a public Let's Encrypt wildcard certificate
- only hosts explicitly listed in the Caddy config are proxied
- nothing needs to be exposed on your router

The wildcard certificate is issued with DNS-01 validation through Google Cloud DNS using `lego`. DNS-01 proves ownership by creating temporary `_acme-challenge.lab.adre.me` TXT records, so ports 80 and 443 do not need to be exposed publicly.

### Browser-Trusted HTTPS

The domain `adre.me` uses Google Cloud DNS nameservers. To let `lab-edge` issue and renew the trusted certificate:

1. In Google Cloud, identify the project that hosts the public Cloud DNS zone for `adre.me`.
2. Create a service account for ACME DNS automation.
3. Grant it DNS permissions for the project or zone. The simple option is `roles/dns.admin`; a tighter custom role should allow reading the managed zone and creating/deleting DNS changes and record sets.
4. Create a JSON key for that service account and place it at the path from `EDGE_ACME_GCLOUD_SERVICE_ACCOUNT_FILE`, for example `/home/drew/documents/personal/homelab/.secrets/adre-me-cloud-dns.json`.
5. Set `EDGE_ACME_EMAIL` and `EDGE_ACME_GCLOUD_PROJECT` in `.env`, then source `.env` before running Ansible.

```sh
export EDGE_ACME_EMAIL="you@example.com"
export EDGE_ACME_GCLOUD_PROJECT="your-google-cloud-project-id"
export EDGE_ACME_GCLOUD_SERVICE_ACCOUNT_FILE="/home/drew/documents/personal/homelab/.secrets/adre-me-cloud-dns.json"
```

No permanent public `A`, `AAAA`, or `CNAME` record is required for `*.lab.adre.me` as long as access stays LAN-only. AdGuard keeps resolving `*.lab.adre.me` to `lab-edge` internally. `lego` will create and remove temporary TXT records under:

```text
_acme-challenge.lab.adre.me
```

The certificate state is stored on `lab-edge` under `/var/lib/lego/`. The active certificate and key are copied to `/etc/caddy/certs/` with permissions Caddy can read. A systemd timer named `lego-edge-cert-renew.timer` renews the certificate daily when it is close to expiry and reloads Caddy after renewal.

Additional app hostnames should be added to `edge_extra_services` in [ansible/inventory/group_vars/all.yml](/home/drew/documents/personal/homelab/ansible/inventory/group_vars/all.yml:1). The wildcard DNS rewrite means any `*.lab.adre.me` hostname will already resolve to `lab-edge`; you only need to tell Caddy which upstream each hostname should proxy to.

## Ansible

`tofu output ansible_inventory` prints an inventory snippet you can save or feed into a follow-on Ansible workflow after the guests are provisioned.

### Ansible Usage

After `tofu apply`, render inventory from state:

```sh
./scripts/render-ansible-inventory.sh
```

If you need a static example instead of rendering from OpenTofu, copy `ansible/inventory/hosts.ini.example` to `ansible/inventory/hosts.ini` and edit it manually.

Export any runtime secrets before running the playbook:

```sh
ansible-galaxy collection install -r ansible/requirements.yml
export ADGUARD_ADMIN_PASSWORD_BCRYPT='replace-with-bcrypt-hash'
export EDGE_ACME_EMAIL="you@example.com"
export EDGE_ACME_GCLOUD_PROJECT="your-google-cloud-project-id"
export EDGE_ACME_GCLOUD_SERVICE_ACCOUNT_FILE="/home/drew/documents/personal/homelab/.secrets/adre-me-cloud-dns.json"
```

Ansible is configured to use `/home/drew/.ssh/root@172.16.0.200`, the same key injected into the guests by Terraform. If you change `TF_VAR_ssh_public_key`, update `private_key_file` in [ansible/ansible.cfg](/home/drew/documents/personal/homelab/ansible/ansible.cfg:1) to the matching private key.

To generate the AdGuard password hash on a machine with `htpasswd` available:

```sh
htpasswd -bnBC 10 "" 'your-password' | tr -d ':\n'
```

Then run:

```sh
uv venv .venv
UV_CACHE_DIR=.uv-cache uv pip install ansible
cd ansible
ANSIBLE_HOME=../.ansible ANSIBLE_LOCAL_TEMP=../.ansible/tmp ../.venv/bin/ansible-galaxy collection install -r requirements.yml
ANSIBLE_HOME=../.ansible ANSIBLE_LOCAL_TEMP=../.ansible/tmp ../.venv/bin/ansible-playbook playbooks/site.yml
```

The `ANSIBLE_HOME` and `ANSIBLE_LOCAL_TEMP` values keep generated Ansible files inside this project directory.

### What Ansible Configures

- `common`: base packages, timezone, and guest agent
- `adguard`: AdGuard Home installation plus a generated config
- `edge`: Caddy for local wildcard HTTPS and proxying
- `docker_host`: Docker Engine and a compose root for non-critical apps
- `jellyfin`: Jellyfin package install and media directories

## Jellyfin Storage Model

Jellyfin now runs as an unprivileged LXC sized for mostly direct-play streaming rather than a larger VM.

- Root filesystem stays small on `lxc_storage`
- Media stays on the Proxmox host, optionally on an external SSD
- Set `jellyfin_media_bind_mount_host_path` to bind-mount that host path into the container at `/srv/media`

Suggested pattern for an external SSD:

1. Mount the SSD on the Proxmox host with a stable path such as `/mnt/media`.
2. Set `jellyfin_media_bind_mount_host_path = "/mnt/media"` in `terraform.tfvars`.
3. Keep Jellyfin metadata and config inside the container, while treating the mounted media path as the library source.

Because the container is unprivileged, make sure the mounted media path is readable by the container. World-readable media files are the simplest option for a read-mostly library.
