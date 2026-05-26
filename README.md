# Homelab OpenTofu

This directory provisions a small Proxmox homelab optimized for a single 16 GB laptop host:

- `lab-adguard` as a core-platform LXC for AdGuard Home
- `lab-edge` as a core-platform LXC for reverse proxy, Tailscale ingress, and browser-trusted local HTTPS
- `lab-monitoring` as a metrics, dashboards, and alerts LXC
- `lab-authelia` as a core-platform LXC for SSO and forward auth
- `lab-lldap` as a core-platform LXC for user directory services
- `lab-jellyfin` as a lean LXC with optional host bind-mounted media storage
- optional media automation LXCs for Arr services and qBittorrent

The checked-in defaults target the existing Proxmox node `norman` at `192.168.1.200` on `192.168.1.0/24`. The Proxmox host IP is managed outside this project and is not changed by Terraform.

## Architecture

The default control plane is intentionally split by ownership:

- OpenTofu owns Proxmox resources: containers, VMIDs, CPU, memory, disks, network addresses, bind mounts, and provider-managed DNS or tailnet settings.
- NixOS owns guest configuration: users, services, secrets, firewall rules, persistence, and package state.
- deploy-rs is the default NixOS deployment path. Host self-upgrade is disabled by default so deploy failures have one primary control loop to inspect.
- Ansible remains for legacy/bootstrap workflows only; new steady-state service configuration should move into the Nix flake.

The core platform is `lab-adguard`, `lab-edge`, `lab-monitoring`, `lab-authelia`, and `lab-lldap`. These services get more memory than the smallest media guests because DNS, ingress, monitoring, auth, and directory lookups should stay healthy before optional apps do.

## Prerequisites

- OpenTofu installed locally
- A Proxmox API token with permissions to create LXCs and, if enabled, VMs
- Debian and NixOS LXC templates already available in Proxmox storage
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
- `lab-monitoring`: `192.168.1.212`
- `lab-authelia`: `192.168.1.213`
- `lab-lldap`: `192.168.1.214`
- `lab-jellyfin`: `192.168.1.230`
- `lab-arr`: disabled until `enable_arr_stack = true`
- `lab-qbittorrent`: disabled until `enable_qbittorrent = true`

An existing unmanaged container named `adguard` may coexist with these resources. Terraform only manages guests present in its state.

## Service split

- `lab-adguard`: AdGuard Home only
- `lab-edge`: reverse proxy and browser-trusted wildcard HTTPS
- `lab-monitoring`: Grafana, Prometheus, Alertmanager, and the central node dashboard
- `lab-authelia`: SSO and forward auth
- `lab-lldap`: LDAP user directory
- `lab-jellyfin`: Jellyfin and a bind-mounted media path from the Proxmox host
- `lab-arr`: Radarr, Sonarr, Prowlarr, Bazarr, and Byparr
- `lab-qbittorrent`: qBittorrent

For local-only HTTPS:

- AdGuard rewrites `*.lab.adre.me` to `lab-edge`
- nginx in `lab-edge` serves `*.lab.adre.me` with a public Let's Encrypt wildcard certificate
- only hosts explicitly listed in the nginx virtual host config are proxied
- nothing needs to be exposed on your router

Friendly service names are preferred for day-to-day use:

- `lab.adre.me` or `grafana.lab.adre.me` for Grafana
- `prometheus.lab.adre.me` for Prometheus
- `alerts.lab.adre.me` for Alertmanager
- `watch.lab.adre.me` for Jellyfin
- `movies.lab.adre.me` for Radarr
- `tv.lab.adre.me` for Sonarr
- `search.lab.adre.me` or `indexers.lab.adre.me` for Prowlarr
- `subtitles.lab.adre.me` for Bazarr
- `downloads.lab.adre.me` or `torrents.lab.adre.me` for qBittorrent

The app-native names such as `jellyfin.lab.adre.me`, `radarr.lab.adre.me`, `sonarr.lab.adre.me`, `prowlarr.lab.adre.me`, `bazarr.lab.adre.me`, and `qbittorrent.lab.adre.me` remain valid aliases.

### Monitoring

`lab-monitoring` runs Grafana on port `3000`, Prometheus on port `9090`, and Alertmanager on port `9093`. Every NixOS host enables the Prometheus node exporter on port `9100`, and the monitoring host scrapes the always-on hosts from [nix/lib/hosts.nix](/home/drew/code/personal/homelab/nix/lib/hosts.nix:1). Optional Arr and qBittorrent hosts are excluded from the default scrape set until those LXCs are enabled.

Grafana is the default dashboard at `https://lab.adre.me` and is also available at `https://grafana.lab.adre.me`. Prometheus and Alertmanager are proxied through nginx at `https://prometheus.lab.adre.me` and `https://alerts.lab.adre.me`; these routes use the same Authelia forward-auth guard as the other internal admin tools.

The provisioned dashboard covers host availability, CPU, memory, root filesystem usage, and load average. Prometheus includes initial alerts for node exporter outages, high memory usage, and root filesystem usage over 85%. The default Alertmanager receiver is intentionally a no-op until a notification target is added.

The wildcard certificate is issued with DNS-01 validation through Cloudflare using NixOS `security.acme`. DNS-01 proves ownership by creating temporary `_acme-challenge.lab.adre.me` TXT records, so ports 80 and 443 do not need to be exposed publicly.

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

No permanent public `A`, `AAAA`, or `CNAME` record is required for `*.lab.adre.me` as long as access stays LAN-only. AdGuard keeps resolving `*.lab.adre.me` to `lab-edge` internally. The ACME DNS provider will create and remove temporary TXT records under:

```text
_acme-challenge.lab.adre.me
```

The certificate state is stored on `lab-edge` under `/var/lib/acme/` and is persisted across container restarts. nginx reads the certificate through the NixOS virtual host configuration and reloads after ACME renewal.

OpenTofu can manage public Cloudflare DNS records. The checked-in example includes CAA records allowing Let's Encrypt to issue for `adre.me`, `lab.adre.me`, and `*.lab.adre.me`; keep `enable_cloudflare_dns = false` until Cloudflare API credentials are configured. If `cloudflare_zone_id` is left empty, OpenTofu looks up the `adre.me` zone by name.

The NixOS edge module requests a certificate for both `lab.adre.me` and `*.lab.adre.me` and wires that certificate into nginx.

Additional app hostnames should be added to the nginx virtual hosts in [nix/hosts/edge/default.nix](/home/drew/code/personal/homelab/nix/hosts/edge/default.nix:93). The wildcard DNS rewrite means any `*.lab.adre.me` hostname will already resolve to `lab-edge`; you only need to tell nginx which upstream each hostname should proxy to.

### Remote Access with Tailscale

This lab uses Tailscale on `lab-edge` for private remote access without router port forwards or a static ISP IP. `lab-edge` advertises four narrow subnet routes by default:

- `192.168.1.210/32` for AdGuard split DNS
- `192.168.1.211/32` for the nginx edge proxy
- `192.168.1.230/32` for Jellyfin (direct streaming, bypasses nginx)

OpenTofu can manage the Tailscale admin-console pieces through the official Tailscale provider. Set a Tailscale API token outside source control:

```sh
export TF_VAR_tailscale_api_key="tskey-api-..."
export TF_VAR_tailscale_tailnet="-"
```

Then enable the tailnet-wide settings:

```hcl
enable_tailscale_management = true
```

The first OpenTofu apply will generate an auth key, enable MagicDNS, and configure split DNS for `lab.adre.me` to use AdGuard at `192.168.1.210`. Export the generated key before running Ansible:

```sh
export TAILSCALE_AUTH_KEY="$(tofu output -raw tailscale_edge_auth_key)"
```

If you prefer not to let OpenTofu generate the auth key, create one in the Tailscale admin console and export it manually:

```sh
export TAILSCALE_AUTH_KEY="tskey-auth-..."
```

The Proxmox role grants `/dev/net/tun` to the `lab-edge` LXC and reboots that container only when the TUN config changes. The Tailscale role installs the Tailscale Debian package, enables IP forwarding, starts `tailscaled`, and runs `tailscale up` with the advertised routes.

After the first Ansible run, `lab-edge` should be joined to the tailnet. Enable device management and apply OpenTofu again:

```hcl
enable_tailscale_edge_device_management = true
```

That second apply approves the advertised subnet routes for AdGuard, nginx, and Jellyfin, and disables key expiry for `lab-edge`.

Once approved, remote clients connected to your tailnet should resolve `jellyfin.lab.adre.me`, `movies.lab.adre.me`, `downloads.lab.adre.me`, and other configured lab hosts through AdGuard, then reach nginx on `lab-edge` over the Tailscale route.

### qBittorrent over Proton VPN

Set `enable_qbittorrent = true` to create `lab-qbittorrent`. When the Arr stack is enabled, Radarr and Sonarr use that LXC as their qBittorrent download client instead of running qBittorrent locally.

Export a Proton VPN Plus WireGuard config before running Ansible. The config should be a P2P-capable Proton server config encoded as base64:

```sh
export PROTONVPN_WIREGUARD_CONFIG_B64="$(base64 -w0 ~/Downloads/protonvpn-wireguard.conf)"
```

The qBittorrent role installs WireGuard, nftables, and qBittorrent; writes the Proton config to `/etc/wireguard/wg0.conf`; starts `wg-quick@wg0`; and installs an nftables kill switch. LAN traffic to `192.168.1.0/24` remains allowed so `lab-edge`, Radarr, and Sonarr can reach the qBittorrent WebUI/API, while internet-bound traffic is only allowed through `wg0`. qBittorrent binds to `wg0` and listens on `qbittorrent_listen_port`, defaulting to `6881`.

If you enable Proton port forwarding, set `qbittorrent_listen_port` to the currently forwarded port before running the qBittorrent role. Proton can rotate forwarded ports between VPN sessions, so fully automatic port refresh should be added separately if you rely on inbound peer connectivity.

Remote access still flows through Tailscale on `lab-edge`:

```text
remote client -> Tailscale -> lab-edge nginx -> lab-qbittorrent:8080
```

Do not install Tailscale on `lab-qbittorrent` unless you want direct tailnet access to that host. The default design keeps one Tailscale ingress point and uses nginx for `downloads.lab.adre.me`.

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
- `edge`: nginx for local wildcard HTTPS and proxying
- `jellyfin`: Jellyfin package install and media directories

## Jellyfin Storage Model

Jellyfin now runs as an unprivileged LXC sized for mostly direct-play streaming rather than a larger VM.

- Root filesystem is sized by `lxc_resources.jellyfin.disk_gb` on `lxc_storage`; the default value is 16 GiB
- Media stays on the Proxmox host, optionally on an external SSD
- Set `jellyfin_media_bind_mount_host_path` to bind-mount that host path into the container at `/mnt/media`

When no bind mount is configured, Jellyfin stores media on the container root filesystem. Increase `lxc_resources.jellyfin.disk_gb` to grow that filesystem in place; do not decrease it unless you have migrated the data elsewhere.

Suggested pattern for an external SSD:

1. Mount the SSD on the Proxmox host with a stable path such as `/mnt/media`.
2. Set `jellyfin_media_bind_mount_host_path = "/mnt/media"` in `terraform.tfvars`.
3. Keep Jellyfin metadata and config inside the container, while treating the mounted media path as the library source.

Because the container is unprivileged, make sure the mounted media path is readable by the container. World-readable media files are the simplest option for a read-mostly library.
