# Homelab OpenTofu

This repo is migrating from many NixOS LXCs to one consolidated NixOS VM:

- `lab-core` as a NixOS VM for DNS, reverse proxy, TLS, Tailscale, auth, monitoring, media apps, and downloads
- declarative service configuration only; old service state is intentionally not migrated
- external SSD media/download content is left untouched and can be mounted into the VM later

The legacy LXC resources are still present so the active AdGuard DNS container can remain online while `lab-core` is built and validated on a temporary IP.

The checked-in defaults target the existing Proxmox node `norman` at `192.168.1.200` on `192.168.1.0/24`. The Proxmox host IP is managed outside this project and is not changed by Terraform.

## Architecture

The target control plane is intentionally split by ownership:

- OpenTofu owns Proxmox resources: the `lab-core` VM, VMID, CPU, memory, disk, network address, and provider-managed DNS or tailnet settings.
- NixOS owns guest configuration: users, services, secrets, firewall rules, app settings, and package state.
- deploy-rs is the NixOS deployment path. Host self-upgrade is disabled by default so deploy failures have one primary control loop to inspect.

The legacy LXC layout remains in the repo for rollback and reference during migration.

## Prerequisites

- OpenTofu installed locally
- A Proxmox API token with permissions to create VMs and legacy LXCs
- A NixOS cloud-init VM template in Proxmox for `lab-core`
- NixOS LXC templates only if continuing to manage the legacy LXC resources
- A local `.env` file exporting secret `TF_VAR_*` values plus `TF_VAR_ssh_public_key`

## Secrets

Create a local `.env` and load it before running OpenTofu:

```sh
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
$EDITOR .env
set -a
source .env
set +a
```

Provisioned guests are managed over SSH keys only. `TF_VAR_ssh_public_key` is injected during provisioning as the launch/bootstrap key, and deploy-rs uses that key to connect as `root`.

## Usage

Update `terraform/terraform.tfvars` for your node name, storage names, template IDs, and static IPs. To build the new VM without touching router DNS, set:

```hcl
enable_core_vm         = true
core_vm_template_vm_id = 9000
core_vm_ip             = "192.168.1.220"
```

Then run:

```sh
cd terraform
tofu init
tofu fmt
tofu validate
tofu plan
tofu apply
```

After OpenTofu provisions `lab-core`, deploy the consolidated NixOS host:

```sh
cd nix
nix run .#deploy-core
```

Legacy one-off host deploys remain available while the old LXCs exist:

```sh
nix run .#deploy-rs -- .#arr
nix run .#deploy-rs -- .#qbittorrent
```

For the current `norman` host, the default managed addresses are:

- `lab-core`: `192.168.1.220` during validation; cut over to `192.168.1.210` after stopping the old AdGuard LXC
- `lab-adguard`: `192.168.1.210`
- `lab-edge`: `192.168.1.211`
- `lab-monitoring`: `192.168.1.212`
- `lab-authelia`: `192.168.1.213`
- `lab-lldap`: `192.168.1.214`
- `lab-jellyfin`: `192.168.1.230`
- `lab-arr`: disabled until `enable_arr_stack = true`
- `lab-qbittorrent`: disabled until `enable_qbittorrent = true`

An existing unmanaged container named `adguard` may coexist with these resources. Terraform only manages guests present in its state.

## Single-VM Migration

The migration is a rebuild, not a state migration:

1. Provision `lab-core` on `192.168.1.220`.
2. Deploy `nix#core`.
3. Test DNS directly against the temporary IP:

   ```sh
   dig @192.168.1.220 google.com
   dig @192.168.1.220 lab.adre.me
   dig @192.168.1.220 jellyfin.lab.adre.me
   ```

4. Confirm AdGuard's declarative blocklists, custom rules, and wildcard rewrites are present.
5. Stop the old AdGuard LXC at `192.168.1.210`.
6. Change both `terraform.core_vm_ip` and `nix/lib/hosts.nix` for `core.ip` to `192.168.1.210`.
7. Apply OpenTofu or update the VM IP, then redeploy/reboot `lab-core`.
8. Verify DNS at the router's unchanged DNS target:

   ```sh
   dig @192.168.1.210 google.com
   dig @192.168.1.210 lab.adre.me
   ```

9. Stop the remaining LXCs after the core VM is working.

The external SSD currently used by Jellyfin and the Arr stack should not be copied or reformatted. Mount it into the VM later at `/srv/media` and, if desired, `/srv/downloads`.

## Target Service Split

`lab-core` runs these roles on one NixOS VM:

- AdGuard Home for router-facing DNS on port 53
- nginx and ACME for local HTTPS
- Tailscale for remote private access
- Authelia and LLDAP for auth
- Grafana, Prometheus, Alertmanager, and node exporter for monitoring
- Jellyfin, Radarr, Sonarr, Prowlarr, Bazarr, and qBittorrent

The old per-service LXC split remains below as legacy reference during cutover:

- `lab-adguard`: AdGuard Home only
- `lab-edge`: reverse proxy and browser-trusted wildcard HTTPS
- `lab-monitoring`: Grafana, Prometheus, Alertmanager, and the central node dashboard
- `lab-authelia`: SSO and forward auth
- `lab-lldap`: LDAP user directory
- `lab-jellyfin`: Jellyfin and a bind-mounted media path from the Proxmox host
- `lab-arr`: Radarr, Sonarr, Prowlarr, Bazarr, and Byparr
- `lab-qbittorrent`: qBittorrent

For local-only HTTPS:

- AdGuard rewrites `*.lab.adre.me` to `lab-core`
- nginx in `lab-core` serves `*.lab.adre.me` with a public Let's Encrypt wildcard certificate
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

In the target VM layout, `lab-core` runs Grafana, Prometheus, Alertmanager, and node exporter locally. The old `lab-monitoring` notes below apply only to the legacy LXC layout.

`lab-monitoring` runs Grafana on port `3000`, Prometheus on port `9090`, and Alertmanager on port `9093`. Every NixOS host enables the Prometheus node exporter on port `9100`, and the monitoring host scrapes the always-on hosts from [nix/lib/hosts.nix](/home/drew/code/personal/homelab/nix/lib/hosts.nix:1). Optional Arr and qBittorrent hosts are excluded from the default scrape set until those LXCs are enabled.

Grafana is the default dashboard at `https://lab.adre.me` and is also available at `https://grafana.lab.adre.me`. Prometheus and Alertmanager are proxied through nginx at `https://prometheus.lab.adre.me` and `https://alerts.lab.adre.me`; these routes use the same Authelia forward-auth guard as the other internal admin tools.

The provisioned dashboard covers host availability, CPU, memory, root filesystem usage, and load average. Prometheus includes initial alerts for node exporter outages, high memory usage, and root filesystem usage over 85%. The default Alertmanager receiver is intentionally a no-op until a notification target is added.

The wildcard certificate is issued with DNS-01 validation through Cloudflare using NixOS `security.acme`. DNS-01 proves ownership by creating temporary `_acme-challenge.lab.adre.me` TXT records, so ports 80 and 443 do not need to be exposed publicly.

### Browser-Trusted HTTPS

The domain `adre.me` is hosted on Cloudflare DNS. In the target VM layout, `lab-core` issues and renews the trusted certificate with Cloudflare's API:

1. In Cloudflare, create an API token with Zone:Read and DNS:Edit for `adre.me`.
2. Set `EDGE_ACME_EMAIL`, `CLOUDFLARE_DNS_API_TOKEN`, `CLOUDFLARE_API_TOKEN`, and the matching `TF_VAR_...` export in `.env`, then source `.env` before running OpenTofu or deploying NixOS.

```sh
export EDGE_ACME_EMAIL="drewnorman739@gmail.com"
export CLOUDFLARE_DNS_API_TOKEN="replace-me"
export CLOUDFLARE_API_TOKEN="${CLOUDFLARE_DNS_API_TOKEN}"
export TF_VAR_cloudflare_api_token="${CLOUDFLARE_DNS_API_TOKEN}"
```

No permanent public `A`, `AAAA`, or `CNAME` record is required for `*.lab.adre.me` as long as access stays LAN-only. AdGuard keeps resolving `*.lab.adre.me` to `lab-core` internally. The ACME DNS provider will create and remove temporary TXT records under:

```text
_acme-challenge.lab.adre.me
```

The certificate state is stored on `lab-core` under `/var/lib/acme/`. nginx reads the certificate through the NixOS virtual host configuration and reloads after ACME renewal.

OpenTofu can manage public Cloudflare DNS records. The checked-in example includes CAA records allowing Let's Encrypt to issue for `adre.me`, `lab.adre.me`, and `*.lab.adre.me`; keep `enable_cloudflare_dns = false` until Cloudflare API credentials are configured. If `cloudflare_zone_id` is left empty, OpenTofu looks up the `adre.me` zone by name.

The NixOS edge module requests a certificate for both `lab.adre.me` and `*.lab.adre.me` and wires that certificate into nginx.

Additional app hostnames should be added to the nginx virtual hosts in [nix/hosts/core/default.nix](/home/drew/code/personal/homelab/nix/hosts/core/default.nix:229). The wildcard DNS rewrite means any `*.lab.adre.me` hostname will already resolve to `lab-core`; you only need to tell nginx which upstream each hostname should proxy to.

### Remote Access with Tailscale

This lab uses Tailscale on `lab-core` for private remote access without router port forwards or a static ISP IP. `lab-core` advertises the lab subnet route by default:

- `192.168.1.0/24` for lab services behind AdGuard and nginx

OpenTofu can manage the Tailscale admin-console pieces through the official Tailscale provider. Set a Tailscale API token outside source control:

```sh
export TF_VAR_tailscale_api_key="tskey-api-..."
export TF_VAR_tailscale_tailnet="-"
```

Then enable the tailnet-wide settings:

```hcl
enable_tailscale_management = true
```

The first OpenTofu apply will generate an auth key, enable MagicDNS, and configure split DNS for `lab.adre.me` to use AdGuard at `192.168.1.210`. Store the generated key in the shared edge/core sops secret before deploying NixOS:

```sh
export TAILSCALE_AUTH_KEY="$(tofu -chdir=terraform output -raw tailscale_core_auth_key)"
```

If you prefer not to let OpenTofu generate the auth key, create one in the Tailscale admin console and export it manually:

```sh
export TAILSCALE_AUTH_KEY="tskey-auth-..."
```

The `lab-core` VM runs Tailscale natively, including IP forwarding and the advertised route.

After the first NixOS deploy, `lab-core` should be joined to the tailnet. Enable device management and apply OpenTofu again:

```hcl
enable_tailscale_core_device_management = true
```

That second apply approves the advertised subnet route and disables key expiry for the managed Tailscale device.

Once approved, remote clients connected to your tailnet should resolve `jellyfin.lab.adre.me`, `movies.lab.adre.me`, `downloads.lab.adre.me`, and other configured lab hosts through AdGuard, then reach nginx on `lab-core` over Tailscale.

### qBittorrent

qBittorrent now runs on `lab-core` with a fresh declarative config. When the Arr stack is used, Radarr and Sonarr should point at `127.0.0.1:8080` or `downloads.lab.adre.me`.

The qBittorrent NixOS module currently runs `qbittorrent-nox` on port `8080` with persisted config under `/var/lib/qbittorrent`. VPN isolation is not currently implemented in the NixOS module; add WireGuard and firewall policy there before relying on this host for VPN-bound downloads.

Remote access flows through Tailscale on `lab-core`:

```text
remote client -> Tailscale -> lab-core nginx -> qBittorrent:8080
```

The default design keeps one Tailscale ingress point and uses nginx for `downloads.lab.adre.me`.

## Jellyfin Storage Model

Jellyfin now runs on `lab-core`. Its service state starts fresh; the existing external SSD media should be mounted into the VM later.

- Root filesystem is sized by `core_vm_disk_gb` on `core_vm_storage`; the default value is 96 GiB
- Media stays on the external SSD and is not copied during migration
- Mount the media path into the VM at `/srv/media` later

When no external media mount is configured, Jellyfin starts with an empty library.

Suggested pattern for an external SSD:

1. Attach or pass through the SSD to the VM.
2. Mount it at `/srv/media`.
3. Point Jellyfin, Radarr, and Sonarr at `/srv/media/movies` and `/srv/media/tv`.
