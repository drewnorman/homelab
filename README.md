# Homelab OpenTofu

This repo manages one consolidated NixOS VM:

- `lab-core` as a NixOS VM for DNS, reverse proxy, TLS, Tailscale, auth, monitoring, media apps, and downloads
- reproducible service configuration through OpenTofu, NixOS, deploy-rs, and sops-nix
- external SSD media/download content is managed outside the VM root disk and can be mounted at `/srv/media`

The checked-in defaults are for the Proxmox node `norman` at `192.168.1.200` on `192.168.1.0/24`. The Proxmox host IP is managed outside this project and is not changed by Terraform.

## Architecture

The control plane is intentionally split by ownership:

- OpenTofu owns Proxmox resources: the `lab-core` VM, VMID, CPU, memory, disk, network address, and provider-managed DNS or tailnet settings.
- NixOS owns guest configuration: users, services, secrets, firewall rules, app settings, and package state.
- deploy-rs is the NixOS deployment path. Host self-upgrade is disabled by default so deploy failures have one primary control loop to inspect.

Reproducibility comes from the checked-in Terraform, Nix flake, host metadata, service modules, and encrypted sops files. Runtime content such as media files and application databases is intentionally outside the declarative source of truth unless a service module explicitly manages it.

## Prerequisites

- OpenTofu installed locally
- A Proxmox API token with permissions to create and manage the `lab-core` VM
- A NixOS cloud-init VM template in Proxmox for `lab-core`
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

Update `terraform/terraform.tfvars` for your node name, storage names, template VMID, and static IP. The default layout keeps `lab-core` on the router DNS address:

```hcl
enable_core_vm         = true
core_vm_template_vm_id = 9000
core_vm_ip             = "192.168.1.210"
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

If Nix is not installed locally, run deploys through Podman with a persistent
Nix store volume. Create the volume once:

```sh
podman volume create homelab-nix-store
```

Then run deploys from the repo root:

```sh
podman run --rm \
  -e 'NIX_CONFIG=experimental-features = nix-command flakes' \
  -v homelab-nix-store:/nix \
  -v "$PWD":/workspace \
  -v "$HOME/.ssh":/root/.ssh:ro \
  -w /workspace/nix \
  docker.io/nixos/nix:latest \
  nix run .#deploy-core -- --skip-checks --ssh-opts '-i /root/.ssh/drew@x1c-g9 -F /dev/null'
```

The named volume keeps downloaded Nix paths between runs, avoiding the cold
store rebuild behavior of one-shot containers.

For the default `norman` host, the managed address is:

- `lab-core`: `192.168.1.210`

If stale provider-managed resources from optional Cloudflare or Tailscale management remain in state while those integrations are disabled, remove those stale state entries or re-enable the matching credentials before expecting a full clean plan.

External SSD media for Jellyfin and the Arr stack is kept outside the VM root disk. OpenTofu attaches the Samsung T7 partition to VM 120 with a root-only Proxmox `qm set` provisioner, and NixOS mounts it by filesystem UUID; see [terraform/core-vm.tf](/home/drew/code/personal/homelab/terraform/core-vm.tf:1) and [nix/hosts/core/default.nix](/home/drew/code/personal/homelab/nix/hosts/core/default.nix:27).

### VM Template Assumptions

The `core` NixOS host defaults are recorded in [nix/lib/hosts.nix](/home/drew/code/personal/homelab/nix/lib/hosts.nix:2):

- network interface: `ens18`
- boot device: `/dev/vda`
- root filesystem: `/dev/disk/by-label/nixos`
- root filesystem type: `ext4`

If the Proxmox template uses different names, update those host metadata fields before deploying `.#core`.

## Service Layout

`lab-core` runs these roles on one NixOS VM:

- AdGuard Home for router-facing DNS on port 53
- nginx and ACME for local HTTPS
- Tailscale for remote private access
- Authelia and LLDAP for auth
- Grafana, Prometheus, Alertmanager, blackbox exporter, and node exporter for monitoring
- Jellyfin, Radarr, Sonarr, Prowlarr, Bazarr, and qBittorrent

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

In the single VM layout, `lab-core` runs Grafana, Prometheus, Alertmanager, blackbox exporter, and node exporter locally.

Grafana is the default dashboard at `https://lab.adre.me` and is also available at `https://grafana.lab.adre.me`. Prometheus and Alertmanager are proxied through nginx at `https://prometheus.lab.adre.me` and `https://alerts.lab.adre.me`; these routes use the same Authelia forward-auth guard as the other internal admin tools.

The provisioned Grafana dashboards cover homelab overview, host health, service health, and storage/media state. Prometheus checks node exporter, failed systemd units, key filesystem usage, read-only filesystems, public service endpoints, response latency, and TLS expiry.

Alertmanager sends warning and critical alerts to Slack through an incoming webhook. Create a dedicated free Slack workspace and a `#homelab-alerts` channel, then set the webhook URL in `.env` before running `nix/secrets/setup.sh`:

```sh
export SLACK_WEBHOOK_URL="https://hooks.slack.com/services/..."
```

The webhook is stored as the `slack-webhook-url` key in `nix/secrets/edge.yaml`; do not commit the raw URL. Informational alerts remain visible in Prometheus/Alertmanager/Grafana without Slack notifications.

The wildcard certificate is issued with DNS-01 validation through Cloudflare using NixOS `security.acme`. DNS-01 proves ownership by creating temporary `_acme-challenge.lab.adre.me` TXT records, so ports 80 and 443 do not need to be exposed publicly.

### Browser-Trusted HTTPS

The domain `adre.me` is hosted on Cloudflare DNS. In the single VM layout, `lab-core` issues and renews the trusted certificate with Cloudflare's API.

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

The NixOS core module requests a certificate for both `lab.adre.me` and `*.lab.adre.me` and wires that certificate into nginx.

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

The first OpenTofu apply will generate an auth key, enable MagicDNS, and configure split DNS for `lab.adre.me`. Split DNS defaults to `core_vm_ip`; override `tailscale_split_dns_nameserver_ip` if you need to pin it to another resolver.

Store the generated key in the shared edge/core sops secret before deploying NixOS:

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

qBittorrent runs on `lab-core` with declarative service config. When the Arr stack is used, Radarr and Sonarr should point at `127.0.0.1:8080` or `downloads.lab.adre.me`.

The qBittorrent NixOS module runs `qbittorrent-nox` on port `8080` with persisted config under `/var/lib/qbittorrent`. VPN isolation is not implemented in the NixOS module; add WireGuard and firewall policy there before relying on this host for VPN-bound downloads.

Remote access flows through Tailscale on `lab-core`:

```text
remote client -> Tailscale -> lab-core nginx -> qBittorrent:8080
```

The default design keeps one Tailscale ingress point and uses nginx for `downloads.lab.adre.me`.

## Jellyfin Storage Model

Jellyfin runs on `lab-core`. Its service data lives under the VM root disk, while media content is supplied by the external SSD mount.

- Root filesystem is sized by `core_vm_disk_gb` on `core_vm_storage`; the default value is 96 GiB
- Media stays on the external SSD
- The SSD filesystem is mounted at `/srv/storage/external`
- `/srv/storage/external/media` is bind-mounted to `/srv/media`
- `/srv/storage/external/downloads` is bind-mounted to `/srv/downloads`

Current Proxmox attachment:

```sh
qm set 120 --scsi1 /dev/disk/by-uuid/06d2efe6-c0b5-411c-8747-3a4ff0242979,backup=0,discard=on,ssd=1
```

Current NixOS mount source:

```sh
/dev/disk/by-uuid/06d2efe6-c0b5-411c-8747-3a4ff0242979
```

If the SSD is replaced:

1. Attach or pass through the SSD to the VM.
2. Confirm the stable device path with `ls -l /dev/disk/by-label /dev/disk/by-uuid`.
3. Update `externalStorage.device` in [nix/hosts/core/default.nix](/home/drew/code/personal/homelab/nix/hosts/core/default.nix:27).
4. Deploy `.#core`.
5. Point Jellyfin, Radarr, and Sonarr at `/srv/media/movies` and `/srv/media/tv`.
