# Homelab

This repo manages one consolidated NixOS VM:

- `lab-core` as a NixOS VM for DNS, reverse proxy, TLS, Tailscale, auth, monitoring, media apps, and downloads
- reproducible service configuration through OpenTofu, NixOS, deploy-rs, and sops-nix
- external SSD media/download content is managed outside the VM root disk and mounted at `/srv/media` and `/srv/downloads`

The checked-in defaults are for the Proxmox node `norman` at `192.168.1.200` on `192.168.1.0/24`. The Proxmox host IP is managed outside this project and is not changed by OpenTofu.

## Architecture

The control plane is intentionally split by ownership:

- OpenTofu owns Proxmox resources: the `lab-core` VM, VMID, CPU, memory, disk, network address, and provider-managed DNS or tailnet settings.
- A separate OpenTofu root owns the OpenAI project control plane; its Admin key remains operator-local and never reaches Terraform state, CI, sops, or `lab-core`.
- NixOS owns guest configuration: users, services, secrets, firewall rules, app settings, and package state.
- deploy-rs is the NixOS deployment path. Host self-upgrade is disabled by default so deploy failures have one primary control loop to inspect.

Reproducibility comes from the checked-in OpenTofu configuration, Nix flake, host metadata, service modules, and encrypted sops files. Runtime content such as media files and application databases is intentionally outside the declarative source of truth unless a service module explicitly manages it.

## Prerequisites

- OpenTofu installed locally
- A Proxmox API token with permissions to create and manage the `lab-core` VM
- A NixOS cloud-init VM template in Proxmox for `lab-core`
- A local `.env` file exporting secret `TF_VAR_*` values plus `TF_VAR_ssh_public_key`
- A `terraform/terraform.tfvars` file based on `terraform/terraform.tfvars.example`
- An OpenAI Admin API key exported as `OPENAI_ADMIN_KEY` when operating `terraform/openai`

## Secrets

Create `terraform/terraform.tfvars`, then create and load a local `.env` before running OpenTofu:

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

The OpenAI project has an isolated root and state prefix. Its staged rollout,
dashboard-only billing prerequisites, key bootstrap, and negative tests are
documented in [notes/homelab-ai-plan.md](notes/homelab-ai-plan.md):

```sh
cp terraform/openai/terraform.tfvars.example terraform/openai/terraform.tfvars
export OPENAI_ADMIN_KEY='...'
tofu -chdir=terraform/openai init
tofu -chdir=terraform/openai plan -out=tfplan-openai
tofu -chdir=terraform/openai apply tfplan-openai
scripts/bootstrap-openai-key.sh
```

Do not commit `terraform/openai/terraform.tfvars`, a saved plan, or any OpenAI
key. The project and service account use `prevent_destroy`; removing either
guard requires an intentional configuration change and a dedicated plan.

After OpenTofu provisions `lab-core`, deploy the consolidated NixOS host:

```sh
cd nix
nix run .#deploy-core
```

The LAN deploy target uses the static `192.168.1.210` address, avoiding a
dependency on short-hostname DNS. The deploy-rs CLI and its Nix 2.30 runtime
come from the flake-locked nixpkgs binary cache; the compatible runtime avoids
the deploy-rs failure with Nix 2.33 and newer. The deploy-rs input remains the
source of activation helpers and deployment checks.

GitHub Actions runs CI on pull requests to `master` and on pushes to `master`.
CI checks the Nix flake, builds the `core` system closure, and validates the
OpenTofu configuration without touching remote state. CI also requires
Conventional Commit subjects for pushed or pull-request commits. To enable the
same check locally, run:

```sh
git config core.hooksPath .githooks
```

Deploys stay manual from a trusted machine over SSH/Tailscale with deploy-rs.

Recommended GitHub protection for this homelab is intentionally small: protect
`master`, require pull requests before merging, require the `nix` and
`opentofu` checks, require branches to be up to date before merge, and
allow administrators to bypass only for emergency break-glass fixes.

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

External SSD media for Jellyfin and the Arr stack is kept outside the VM root disk. OpenTofu attaches the Samsung T7 partition to `core_vm_id` with a root-only Proxmox `qm set` provisioner, and NixOS mounts it by filesystem UUID; see [terraform/core-vm.tf](/home/drew/code/personal/homelab/terraform/core-vm.tf:1) and [nix/hosts/core/default.nix](/home/drew/code/personal/homelab/nix/hosts/core/default.nix:422).

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
- Dashy for the LAN service portal
- Grafana, Prometheus, Alertmanager, blackbox exporter, and node exporter for monitoring
- Home Assistant for house automation, device integrations, and local Assist voice services
- Frigate for local camera live views and short object-triggered recordings
- Open WebUI for the curated OpenAI-backed household chat service
- Jellyfin, Jellyseerr, Radarr, Sonarr, Prowlarr, Bazarr, and qBittorrent

For local-only HTTPS:

- AdGuard rewrites `*.lab.adre.me` to `lab-core`
- nginx in `lab-core` serves `*.lab.adre.me` with a public Let's Encrypt wildcard certificate
- only hosts explicitly listed in the nginx virtual host config are proxied
- nothing needs to be exposed on your router

Friendly service names are preferred for day-to-day use:

- `lab.adre.me` for the service portal
- `dns.lab.adre.me` for AdGuard Home
- `grafana.lab.adre.me` or `status.lab.adre.me` for Grafana
- `logs.lab.adre.me` for live service logs in Grafana Explore
- `prometheus.lab.adre.me` for Prometheus
- `alerts.lab.adre.me` for Alertmanager
- `house.lab.adre.me` for Home Assistant
- `cams.lab.adre.me` for Frigate cameras
- `ai.lab.adre.me` for Homelab AI
- `watch.lab.adre.me` for Jellyfin
- `catalog.lab.adre.me` for Jellyseerr
- `movies.lab.adre.me` for Radarr
- `tv.lab.adre.me` for Sonarr
- `indexers.lab.adre.me` for Prowlarr
- `subtitles.lab.adre.me` for Bazarr
- `torrents.lab.adre.me` for qBittorrent

The app-native names such as `adguard.lab.adre.me`, `jellyfin.lab.adre.me`, `jellyseerr.lab.adre.me`, `radarr.lab.adre.me`, `sonarr.lab.adre.me`, `prowlarr.lab.adre.me`, `bazarr.lab.adre.me`, and `qbittorrent.lab.adre.me` remain valid aliases.
`assistant.lab.adre.me` is also available as an alias for Home Assistant.
Both names currently use the Authelia gate.

### Cameras

Frigate runs on `lab-core` at `https://cams.lab.adre.me`, behind the existing
Authelia `homelab_admins` policy. nginx terminates HTTPS and proxies to
Frigate's HTTP web port, which is mapped only to `127.0.0.1`. Frigate's
unauthenticated API and RTSP/WebRTC ports are not exposed on the LAN. Remote
browser access follows the existing Tailscale subnet route and split DNS.

Frigate's camera and retention settings live in `nix/assets/frigate/config.yml`.
The service installs this file to `/var/lib/frigate/config/config.yml` on every
start, so UI changes to the Frigate config are replaced on the next restart.
Change the tracked YAML and deploy NixOS instead. Camera credentials live in
the sops-encrypted `nix/secrets/frigate.yaml` and enter the Podman container
through a root-only environment file. Do not put credentials in the tracked
Frigate YAML.

The intended camera hostnames are `thingino-cam-1` and `thingino-cam-2`.
Cam1 answers at `192.168.1.23`, and Cam2 at `192.168.1.24`; both are enabled
in Frigate. Each camera has a 25 fps H.264 mainstream and a 640×360 H.264
substream set to 5 fps. Their `root` logins are separate from their `thingino`
RTSP/ONVIF accounts. Root logins are stored in the operator-only
`nix/secrets/thingino.yaml`; Frigate receives only the RTSP accounts from
`nix/secrets/frigate.yaml`. `lab-core` does not resolve the camera hostnames,
so the tracked config uses their reserved IP addresses.

After flashing each Thingino Wyze v3 camera:

1. Give it a stable address with a router DHCP reservation and confirm its
   main and lower resolution RTSP streams in Thingino. Set both streams to
   H.264 if available, with the lower resolution stream at 5 fps.
2. From `nix/`, make `ssh-to-age` available (`nix shell nixpkgs#ssh-to-age`)
   and edit the encrypted secret with:

   ```sh
   SOPS_AGE_KEY_CMD='ssh-to-age -private-key -i /home/drew/.ssh/drew@x1c-g9' sops secrets/frigate.yaml
   ```

   The operator age recipient was derived from that SSH key, but plain
   `sops secrets/frigate.yaml` cannot use the SSH private key directly to
   decrypt an `age1...` recipient. This command derives the age identity when
   needed without saving a second private key. Replace the camera's
   `REPLACE_ME` values with the account shown under Thingino's **Settings →
   RTSP/ONVIF Access**. The camera's `root` login is not the RTSP account.
   URL-encode any reserved characters in those values because go2rtc reads
   them inside RTSP URLs. Keep them on one line. The file is encrypted when
   saved.
3. Change that camera's `enabled` value to `true` in
   `nix/assets/frigate/config.yml`, then deploy NixOS with `nix run .#deploy-core`
   from the `nix/` directory. The main stream is assigned to recording and
   live viewing, and the lower resolution stream to detection. Use the same
   aspect ratio for both streams where possible.
4. Confirm that the camera appears in Live and that a person, vehicle, cat,
   dog, or bird produces a playable Review item. Ordinary motion without a
   recognized object should not leave a recording.

The default object list is `person`, `car` (including Frigate's default truck
mapping), `motorcycle`, `bicycle`, `bus`, `dog`, `cat`, and `bird`. Continuous and
general motion retention are disabled. Alert and detection clips, including
five seconds before and after each event, are retained for a rolling three
days. Frigate stores media at `/srv/storage/external/cameras/frigate` and will
not start if the external SSD is not mounted. Its configuration and database
stay under `/var/lib/frigate/config` on the VM disk. Exported clips are not
removed by the three-day retention policy.

Check the service and resource use after both cameras are active:

```sh
ssh root@192.168.1.210 'systemctl status podman-frigate --no-pager; podman stats --no-stream frigate'
ssh root@192.168.1.210 'mountpoint /srv/storage/external; df -h /srv/storage/external'
```

If detection falls behind or the shared VM becomes busy, reduce the camera
substream resolution or move Frigate to hardware with an accelerator. The
service's live view uses Frigate's bundled go2rtc; no separate restreaming
service is required.

#### Home Assistant camera integration

`lab-core` runs an authenticated Mosquitto broker at `192.168.1.210:1883` for
Home Assistant, Frigate, and the two Thingino cameras. Each client has its own
password in `nix/secrets/mqtt.yaml`. The broker has no nginx route. Frigate's
MQTT settings are tracked in `nix/assets/frigate/config.yml`; its RTSP restream
is mapped only to host loopback on port 8554 for Home Assistant live views.
Home Assistant includes the Frigate custom component from Nixpkgs.

The live Home Assistant instance has both the MQTT and Frigate integrations
configured. On a fresh Home Assistant data directory, recreate them as follows:

1. In Home Assistant, add **Settings → Devices & services → Add integration →
   MQTT**. Use `192.168.1.210`, port `1883`, username `homeassistant`, and the
   matching password from `nix/secrets/mqtt.yaml`. The [Frigate integration
   guide](https://docs.frigate.video/integrations/home-assistant/) requires this
   shared broker.
2. On each Thingino camera, set `ha.mqtt.host` to `192.168.1.210` and
   `ha.mqtt.username` and `ha.mqtt.password` to that camera's dedicated MQTT
   account in `/etc/thingino.json`. Set `ha.enabled` to `true` and
   `ha.enable_live_view`, `ha.enable_ota`, and `ha.enable_reboot` to `false`,
   then restart `/etc/init.d/S93ha`. Frigate supplies live video. The [Thingino
   guide](https://github.com/themactep/thingino-firmware/blob/master/docs/homeassistant.md)
   describes the discovery entities and commands.
3. In Home Assistant, add the **Frigate** integration with
   `http://127.0.0.1:8971` as its URL. Its packaged component is installed by
   NixOS, so HACS is not required. Confirm both cameras show live video, object
   events, and recordings. Thingino's discovered devices provide motion and
   hardware controls.

Keep `nix/secrets/mqtt.yaml` encrypted when editing credentials. If a password
changes, redeploy NixOS and update the matching Home Assistant or Thingino
client. The Frigate integration uses its own MQTT account automatically.

#### Household dashboard and phone alerts

The Nix-managed **Household** dashboard is at
`https://house.lab.adre.me/household-status/home`. It shows both Frigate
cameras, the two existing Litter-Robots, and any paired LG webOS TV, Roborock,
or Person entities. Its source is `nix/assets/homeassistant/household-status.yaml`;
the alert rules are in `nix/assets/homeassistant/household-automations.yaml`.
The default Home Assistant Overview dashboard remains UI-managed.

1. The Companion App currently cannot complete native login through the
   Authelia-gated Home Assistant routes. After a compatible authenticated route
   is approved and deployed, add that HTTPS URL in the app and sign in with a
   Home Assistant account. Grant notifications and, if desired, location
   access. Keep Tailscale connected when away so the phone can report location
   to the LAN-only Home Assistant instance.
2. In **Settings → People**, attach each phone's `device_tracker` to its
   person. The camera alert requires at least one person and sends only when
   every person is `not_home`; `unknown` or `unavailable` blocks it.
3. In **Developer tools → Actions**, find each phone's
   `notify.mobile_app_...` action. Enter the action names, separated by commas,
   in the **Household mobile notification actions** text helper on the
   dashboard. Until this helper is set, alerts appear as Home Assistant
   persistent notifications. Send a test through the **Send household alert**
   script before relying on phone delivery.
4. If absent, add **LG webOS TV** with the TV on and **Roborock** using its
   existing app account under **Settings → Devices & services**. The already
   configured Whisker integration supplies both Litter-Robots; do not add it
   again.

The alerts cover a Frigate `person` review event while everyone is away, a
Litter-Robot waste drawer at 90% or higher for five minutes, Litter-Robot
status text indicating a fault, and a Roborock vacuum entering its `error`
state. Notifications link back to the related Home Assistant entity. The
dashboard does not issue device commands, and these rules never start or
control the robots or TV. Home Assistant and the alerting logic run on
`lab-core`, so they cannot notify if that VM is down.

### Monitoring

In the single VM layout, `lab-core` runs Grafana, Loki, Grafana Alloy, Prometheus, Alertmanager, blackbox exporter, and node exporter locally.

Dashy is the default portal at `https://lab.adre.me`. nginx guards the portal with Authelia and forwards the authenticated user to Dashy so the dashboard can hide sections by user. Grafana remains available at `https://grafana.lab.adre.me` and `https://status.lab.adre.me`. Prometheus and Alertmanager are proxied through nginx at `https://prometheus.lab.adre.me` and `https://alerts.lab.adre.me`; these routes use the same Authelia forward-auth guard as the other internal admin tools.

The provisioned Grafana dashboards cover homelab overview, host health, service health, and storage/media state. Prometheus checks node exporter, failed systemd units, key filesystem usage, read-only filesystems, public service endpoints, response latency, and TLS expiry.

Grafana also has a Loki datasource fed by Grafana Alloy from the `lab-core` systemd journal. Use `https://logs.lab.adre.me/explore` for a live, filterable log stream. Useful LogQL starting points are `{job="systemd-journal"}`, `{unit="nginx.service"}`, `{unit="qbittorrent.service"}`, and `{level="err"}`.

### Home Assistant Voice

Home Assistant runs at `https://house.lab.adre.me` with `assistant.lab.adre.me`
as an alias. Local Assist services run on `lab-core` through Wyoming:

- faster-whisper on `127.0.0.1:10300` for speech-to-text
- Piper on `127.0.0.1:10200` for text-to-speech, using `en_US-joe-medium`
- openWakeWord on `0.0.0.0:10400` for VM-hosted wake-word detection

For the first room microphone, pass a dedicated USB mic or USB speakerphone
through from the Proxmox host to VM `120`. `lab-core` runs a local Wyoming
satellite named `House USB Mic` on `127.0.0.1:10700`. It is gated on an ALSA
capture device, so the service stays inactive until the USB mic is visible
inside the VM.

After plugging the mic into the Proxmox host, identify its USB vendor/product
ID:

```sh
ssh root@192.168.1.200 'lsusb'
```

Pass it through to `lab-core`, replacing `vvvv:pppp` with the USB ID:

```sh
ssh root@192.168.1.200 'qm set 120 -usb0 host=vvvv:pppp,usb3=1'
```

Then verify the VM sees an ALSA capture device:

```sh
ssh root@192.168.1.210 'lsusb; arecord -l; systemctl status wyoming-satellite --no-pager'
```

If the satellite does not start automatically after hotplug, start it once:

```sh
ssh root@192.168.1.210 'systemctl start wyoming-satellite'
```

The custom wake word is intended to be `Hey Rudy`. Train an openWakeWord model
for that phrase with the upstream openWakeWord training notebook, place the
resulting `.tflite` file under
`/var/lib/wyoming/openwakeword/custom/` on `lab-core`, then add these Wyoming
services in Home Assistant:

- satellite: `tcp://127.0.0.1:10700`
- openWakeWord: `tcp://127.0.0.1:10400`
- faster-whisper: `tcp://127.0.0.1:10300`
- Piper: `tcp://127.0.0.1:10200`

Wake-word detection runs on `lab-core`; the USB mic only provides capture
audio to the VM.

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

Additional app hostnames should be added to the nginx virtual hosts in [nix/hosts/core/default.nix](/home/drew/code/personal/homelab/nix/hosts/core/default.nix:1021). The wildcard DNS rewrite means any `*.lab.adre.me` hostname will already resolve to `lab-core`; you only need to tell nginx which upstream each hostname should proxy to.

Home Assistant voice services expect the Proxmox VM CPU type to expose the host
instruction set. Keep `core_vm_cpu_type = "host"` unless the replacement CPU
model is known to expose AVX-compatible features required by openWakeWord.

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

Once approved, remote clients connected to your tailnet should resolve `jellyfin.lab.adre.me`, `movies.lab.adre.me`, `torrents.lab.adre.me`, and other configured lab hosts through AdGuard, then reach nginx on `lab-core` over Tailscale.

Verify the route and services on `lab-core` after applying OpenTofu:

```sh
ssh root@192.168.1.210 'tailscale status; tailscale debug prefs'
ssh root@192.168.1.210 'sysctl net.ipv4.ip_forward; ss -lntup | grep -E ":(53|80|443)[[:space:]]"'
```

The Tailscale preferences should advertise `192.168.1.0/24`, and the tailnet must approve that same route. For an end-to-end test on a phone, connect Tailscale, enable its DNS settings, disable Wi-Fi, and load `https://lab.adre.me` plus at least one proxied service over cellular data.

### qBittorrent

qBittorrent runs on `lab-core` with declarative service config. When the Arr stack is used, Radarr and Sonarr should point at `127.0.0.1:8080` or `torrents.lab.adre.me`.

The qBittorrent NixOS module runs `qbittorrent-nox` on port `8080` with persisted config under `/var/lib/qbittorrent`. VPN isolation is not implemented in the NixOS module; add WireGuard and firewall policy there before relying on this host for VPN-bound downloads.

Remote access flows through Tailscale on `lab-core`:

```text
remote client -> Tailscale -> lab-core nginx -> qBittorrent:8080
```

The default design keeps one Tailscale ingress point and uses nginx for `torrents.lab.adre.me`.
That vhost is protected by Authelia for members of the `media` LLDAP group. qBittorrent
itself binds the Web UI to `127.0.0.1` and bypasses its native Web UI login for loopback
requests, so users authenticate once through Authelia while nginx and local Arr services can
reach the qBittorrent API without a second app-specific login.

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
3. Update `externalStorage.device` in [nix/hosts/core/default.nix](/home/drew/code/personal/homelab/nix/hosts/core/default.nix:422).
4. Deploy `.#core`.
5. Point Jellyfin, Radarr, and Sonarr at `/srv/media/movies` and `/srv/media/tv`.
