# Homelab OpenTofu

This directory provisions a small Proxmox homelab optimized for a single 16 GB laptop host:

- `lab-adguard` as a lightweight LXC for AdGuard Home
- `lab-edge` as a lightweight LXC for reverse proxy and browser-trusted local HTTPS
- `lab-docker` as a general-purpose VM for non-critical Docker Compose services
- `lab-jellyfin` as a lean LXC with optional host bind-mounted media storage
- `lab-nix` as an always-running NixOS LXC for SSH-accessible lab work

The checked-in defaults target the existing Proxmox node `norman` at `192.168.1.200` on `192.168.1.0/24`. The Proxmox host IP is managed outside this project and is not changed by Terraform.

## Prerequisites

- OpenTofu installed locally
- A Proxmox API token with permissions to create LXCs and, if enabled, VMs
- Debian and NixOS LXC templates already available in Proxmox storage
- A bootstrappable VM template only if `enable_docker_host = true`
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

Keep bcrypt hashes in single quotes in `.env`, for example
`ADGUARD_ADMIN_PASSWORD_BCRYPT='$2b$10$...'`. Unquoted bcrypt hashes are
changed by the shell when `.env` is sourced because `$2b`, `$10`, and similar
segments are treated as parameter expansions.

Provisioned guests are expected to be managed over SSH keys only. `TF_VAR_ssh_public_key` is injected during provisioning as the launch/bootstrap key. After a guest exists, use a per-host SSH key named `~/.ssh/<user>@<fqdn>` for normal connections and Ansible runs.

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

- `lab-adguard`: `192.168.1.210`
- `lab-edge`: `192.168.1.211`
- `lab-jellyfin`: `192.168.1.230`
- `lab-nix`: `192.168.1.240`
- `lab-docker`: disabled until `enable_docker_host = true` and `vm_template_id` is set

An existing unmanaged container named `adguard` may coexist with these resources. Terraform only manages guests present in its state.

## Service split

- `lab-adguard`: AdGuard Home only
- `lab-edge`: reverse proxy and browser-trusted wildcard HTTPS
- `lab-docker`: non-critical self-hosted apps
- `lab-jellyfin`: Jellyfin and a bind-mounted media path from the Proxmox host
- `lab-nix`: NixOS LXC for SSH-accessible lab work

For local-only HTTPS:

- AdGuard rewrites `*.lab.adre.me` to `lab-edge`
- Caddy in `lab-edge` serves `*.lab.adre.me` with a public Let's Encrypt wildcard certificate
- only hosts explicitly listed in the Caddy config are proxied
- nothing needs to be exposed on your router

The wildcard certificate is issued with DNS-01 validation through Cloudflare using `lego`. DNS-01 proves ownership by creating temporary `_acme-challenge.lab.adre.me` TXT records, so ports 80 and 443 do not need to be exposed publicly.

### Browser-Trusted HTTPS

The domain `adre.me` is hosted on Cloudflare DNS. Let `lab-edge` issue and renew the trusted certificate with Cloudflare's API:

1. In Cloudflare, create an API token with Zone:Read and DNS:Edit for `adre.me`.
2. Set `EDGE_ACME_EMAIL`, `CLOUDFLARE_DNS_API_TOKEN`, `CLOUDFLARE_API_TOKEN`, and the matching `TF_VAR_...` export in `.env`, then source `.env` before running OpenTofu or Ansible.

```sh
export EDGE_ACME_EMAIL="drewnorman739@gmail.com"
export CLOUDFLARE_DNS_API_TOKEN="replace-me"
export CLOUDFLARE_API_TOKEN="${CLOUDFLARE_DNS_API_TOKEN}"
export TF_VAR_cloudflare_api_token="${CLOUDFLARE_DNS_API_TOKEN}"
```

No permanent public `A`, `AAAA`, or `CNAME` record is required for `*.lab.adre.me` as long as access stays LAN-only. AdGuard keeps resolving `*.lab.adre.me` to `lab-edge` internally. `lego` will create and remove temporary TXT records under:

```text
_acme-challenge.lab.adre.me
```

The certificate state is stored on `lab-edge` under `/var/lib/lego/`. The active certificate and key are copied to `/etc/caddy/certs/` with permissions Caddy can read. A systemd timer named `lego-edge-cert-renew.timer` renews the certificate daily when it is close to expiry and reloads Caddy after renewal.

OpenTofu can manage public Cloudflare DNS records. The checked-in example includes CAA records allowing Let's Encrypt to issue for `adre.me`, `lab.adre.me`, and `*.lab.adre.me`; keep `enable_cloudflare_dns = false` until Cloudflare API credentials are configured. If `cloudflare_zone_id` is left empty, OpenTofu looks up the `adre.me` zone by name.

The Ansible edge role requests a certificate for both `lab.adre.me` and `*.lab.adre.me`, copies it to `/etc/caddy/certs/`, and fails the run if the active certificate does not include both names.

Additional app hostnames should be added to `edge_extra_services` in [ansible/inventory/group_vars/all.yml](/home/drew/documents/personal/homelab/ansible/inventory/group_vars/all.yml:1). The wildcard DNS rewrite means any `*.lab.adre.me` hostname will already resolve to `lab-edge`; you only need to tell Caddy which upstream each hostname should proxy to.

### Nix Host

The Nix host reserves `lab-nix` at `192.168.1.240` and `nix.lab.adre.me`. When `enable_nix_host = true`, OpenTofu creates an always-running NixOS LXC from `nix_lxc_template_file_id` and includes a `[nix]` Ansible inventory group.

This host is intended for LAN SSH access, not HTTP proxying. AdGuard resolves `nix.lab.adre.me` directly to `192.168.1.240`, so you can connect with:

```sh
ssh -i ~/.ssh/drew@nix.lab.adre.me -o IdentitiesOnly=yes drew@nix.lab.adre.me
```

The intended flake target is:

```text
https://github.com/drewnorman/nix-config#nix
```

OpenTofu downloads the NixOS Proxmox LXC template from Hydra into Proxmox storage when `manage_nix_lxc_template = true`. The configured template file ID is `local:vztmpl/nixos-lxc-lab-nix.tar.xz`.

The local `../nixos-configs` repository also defines the NixOS container configuration and exposes a `lab-nix-lxc-template` package if you need a custom template later:

```sh
cd ../nixos-configs
nix build .#lab-nix-lxc-template
scp -F /dev/null -i ~/.ssh/root@192.168.1.200 -o IdentitiesOnly=yes result/tarball/nixos-system-x86_64-linux.tar.xz root@192.168.1.200:/var/lib/vz/template/cache/nixos-lxc-lab-nix.tar.xz
```

## Ansible

`tofu output ansible_inventory` prints an inventory snippet you can save or feed into a follow-on Ansible workflow after the guests are provisioned.

### Ansible Usage

After `tofu apply`, render inventory from state:

```sh
./scripts/render-ansible-inventory.sh
```

For the upstream NixOS LXC template, bootstrap the `drew` SSH user with raw
Ansible before using the per-host key:

```sh
cd ansible
ANSIBLE_HOME=../.ansible ANSIBLE_LOCAL_TEMP=../.ansible/tmp ../.venv/bin/ansible-playbook playbooks/nix_ssh.yml
```

If you need a static example instead of rendering from OpenTofu, copy `ansible/inventory/hosts.ini.example` to `ansible/inventory/hosts.ini` and edit it manually.

Export any runtime secrets before running the playbook:

```sh
ansible-galaxy collection install -r ansible/requirements.yml
export ADGUARD_ADMIN_PASSWORD_BCRYPT='$2b$10$replace-with-bcrypt-hash'
export EDGE_ACME_EMAIL="drewnorman739@gmail.com"
export CLOUDFLARE_DNS_API_TOKEN="replace-me"
export CLOUDFLARE_API_TOKEN="${CLOUDFLARE_DNS_API_TOKEN}"
export TF_VAR_cloudflare_api_token="${CLOUDFLARE_DNS_API_TOKEN}"
```

Ansible derives per-host private keys from `inventory_hostname`, `ansible_user`, `homelab_name`, and `homelab_domain`, producing names like `~/.ssh/root@edge.lab.adre.me` or `~/.ssh/drew@nix.lab.adre.me`. Terraform still injects `TF_VAR_ssh_public_key` during provisioning; the per-host keys are for post-launch access.

Create local per-host keys whenever you add a host or regenerate inventory:

```sh
ANSIBLE_HOME=../.ansible ANSIBLE_LOCAL_TEMP=../.ansible/tmp ../.venv/bin/ansible-playbook playbooks/ssh_keys.yml
```

To also install those keys on already-launched hosts, run the same playbook with `install_per_host_ssh_keys=true`. If the new per-host key is not installed yet, pass the existing bootstrap key:

```sh
ANSIBLE_HOME=../.ansible ANSIBLE_LOCAL_TEMP=../.ansible/tmp ../.venv/bin/ansible-playbook playbooks/ssh_keys.yml -e install_per_host_ssh_keys=true -e bootstrap_private_key_file=~/.ssh/root@192.168.1.200
```

Then connect with that host's matching key:

```sh
ssh -i ~/.ssh/root@edge.lab.adre.me -o IdentitiesOnly=yes root@edge.lab.adre.me
```

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

- Root filesystem is sized by `jellyfin_lxc_disk_size_gb` on `lxc_storage`; the example value is 16 GiB
- Media stays on the Proxmox host, optionally on an external SSD
- Set `jellyfin_media_bind_mount_host_path` to bind-mount that host path into the container at `/mnt/media`

When no bind mount is configured, Jellyfin stores media on the container root filesystem. Increase `jellyfin_lxc_disk_size_gb` to grow that filesystem in place; do not decrease it unless you have migrated the data elsewhere.

Suggested pattern for an external SSD:

1. Mount the SSD on the Proxmox host with a stable path such as `/mnt/media`.
2. Set `jellyfin_media_bind_mount_host_path = "/mnt/media"` in `terraform.tfvars`.
3. Keep Jellyfin metadata and config inside the container, while treating the mounted media path as the library source.

Because the container is unprivileged, make sure the mounted media path is readable by the container. World-readable media files are the simplest option for a read-mostly library.
