# Netgear DNS relay and DHCP recovery — 2026-11-06

Times are America/Denver (MST). This records the recovery and its tests;
longer-term DNS stability and the cause of the earlier timeouts remain unknown.

## Agent handoff

- Last verified: `x1c-g9` still had `192.168.1.111/24` with gateway
  `192.168.1.1`, and both router `.1` and AdGuard `.210` were reachable.
  The router answered EDNS, plain UDP, and TCP for `lab.adre.me`; 12 of 12
  fresh local EDNS queries and four public EDNS lookups succeeded.
- Router DHCP is active on `.100–.199`; its upstream DNS was restored to
  AdGuard at `.210`. The earlier EDNS timeouts did not recur in this test.
  The underlying cause and longer-term stability remain unknown.
- `norman` and `lab-core` returned at `.200`/`.210`. Proxmox's `vmbr0` was
  already on `.200`, but `/etc/hosts` still mapped `norman` to `.50`, causing
  the console banner to advertise the wrong URL. The host mapping was fixed,
  the banner refreshed, and the Proxmox web page answered at `.200:8006`.
- The first Nix deploy rolled back after the saved Tailscale auth key failed.
  The Tailscale API and VM auth keys were renewed; the guarded deploy then
  succeeded. AdGuard DHCP remained disabled after a service restart. It does
  not listen on UDP 67, while DNS answers on `.210:53`.
- `README.md` and this note document the recovery. The unrelated untracked
  `docs/network-infrastructure-plan.md` belongs to another task; leave it alone.
- The user is weighing OpenWrt. R7450 support and a model-specific factory
  image are published. Firmware Selector can embed first-boot wireless
  settings, so wired access is not an absolute requirement; it remains the
  safer flash/recovery path. No stock reset or firmware flash was performed.
  Both cameras answered HTTP at `.23` and `.24`, but their address mode is
  unverified; revisit them after the router decision.

## Current LAN state

- Netgear R7450 LAN IP/gateway: `192.168.1.1/24`.
- Router upstream DNS: AdGuard Home at `192.168.1.210` (secondary setting
  not verified).
- Router DHCP: enabled, pool `192.168.1.100–192.168.1.199`.
- Router DHCP advertises `192.168.1.1` as DNS; the R7450's documented LAN
  setup does not offer a separate DNS address for DHCP clients.
- `norman` (`192.168.1.200`) and `lab-core` (`192.168.1.210`) are reachable.
  Proxmox services are active and VM 120 (`lab-core`) is running.
- `lab-core` does not listen on UDP 67. The deployed Nix configuration disables
  AdGuard DHCP, including after a service restart. AdGuard remains active for
  DNS on port 53, and `lab.adre.me` resolves to `.210`.
- Proxmox `/etc/hosts` now maps `norman.internal norman` to `.200`; a backup
  of the old file is `/etc/hosts.bak-2026-11-06` on the host. The refreshed
  console banner advertises `https://192.168.1.200:8006/`.
- The original guarded Nix deployment failed when `tailscaled-autoconnect`
  timed out. Tailscale reported `invalid key: API key does not exist`. The
  invalid Tailscale API token and deleted VM auth key were replaced. The new
  VM key was stored in encrypted `nix/secrets/edge.yaml`, and `lab-core`
  authenticated at `100.108.26.98`. The second guarded deploy succeeded.
  OpenTofu now manages the new Tailscale device with its existing
  `192.168.1.0/24` route and device-key expiry disabled; a full plan reports
  no changes. A temporary AdGuard service override was attempted during
  recovery, failed under the unit sandbox, and was removed.

The router configuration was backed up to
`/home/drew/downloads/NETGEAR_R7450.cfg` before the earlier WAN DNS change to
public servers. Applying that change unexpectedly moved the router LAN to
`10.0.0.1/24`, with DHCP still off. Its WAN `100.104.18.55/19` did not overlap
the original LAN.
The cause of the LAN change is unknown. The router LAN was restored to
`192.168.1.1/24` without a factory reset.

At 10:05 MST, `x1c-g9` acquired `192.168.1.111/24` from `192.168.1.1`, with
gateway and DNS both `192.168.1.1`. Router ping, public `1.1.1.1` ping, a
normal system lookup, and HTTPS to `www.example.com` succeeded. This verifies
basic internet use on that client, not every household device or every DNS
query.

## DNS relay evidence

The user reports several months of normal router-to-AdGuard DNS use before
the power flicker. All tests below were performed after that event; they do
not establish that the router relay had a longstanding EDNS problem.

- Before the DHCP migration, 25 of 25 fresh UDP EDNS queries through the
  router timed out while direct AdGuard and Cloudflare queries were fast.
  Router queries over TCP or UDP without EDNS succeeded.
- With the router's WAN DNS now set to public servers, fresh UDP EDNS queries
  to `192.168.1.1` still time out. UDP without EDNS answered in 134 ms;
  TCP with EDNS answered in 24 ms in the same run.
- An EDNS UDP query with a 512-byte advertised buffer timed out. The same
  name had just received a valid no-EDNS answer from the router in 55 ms, so
  a cold upstream lookup is not required to reproduce the failure.
- Direct UDP EDNS to `1.1.1.1` answered in 14 ms. Changing the router's
  upstream and rebooting it did not remove the router-path failure.

At that stage, the evidence pointed to the router's handling of incoming UDP
EDNS queries. The cause and onset are not known. A state or configuration
problem after the power flicker remains plausible. The installed firmware is
`V1.2.1.92_1.0.1`, matching [NETGEAR's R7450 1.2.1.92 release](https://kb.netgear.com/000066523/R7450-Firmware-Version-1-2-1-92).
The [R7450 manual](https://www.downloads.netgear.com/files/GDC/R7450/R7450_UM_EN.pdf)
says its DHCP service gives clients the router's LAN address as DNS.

## Restoration test

After the user set the router's upstream DNS back to AdGuard at
`192.168.1.210`, the router stayed at `192.168.1.1` and `x1c-g9` retained its
`192.168.1.111/24` lease with default route through `.1`. Both `.1` and
`.210` responded to ping.

- Through the router, `lab.adre.me` returned `192.168.1.210` using UDP EDNS
  with a 512-byte advertised buffer, UDP without EDNS, and TCP.
- Twelve of twelve fresh, unique `*.lab.adre.me` UDP EDNS lookups with a
  1232-byte advertised buffer succeeded through the router.
- UDP EDNS lookups for `example.com`, `cloudflare.com`, `wikipedia.org`, and
  `openai.com` succeeded through the router.
- Direct AdGuard queries and the workstation's normal system lookup for
  `lab.adre.me` returned `.210`.
- An HTTPS request to `www.example.com` returned HTTP 200.

The router relay worked during these tests. This does not identify what caused
the earlier timeouts or prove the problem cannot recur. No factory reset was
performed. DNS forwarded through the router now depends on `lab-core` and
Proxmox being available; DHCP remains on the router.

## Remaining checks

- Confirm the router's secondary upstream DNS setting and monitor ordinary
  client lookups over time. If timeouts recur, repeat paired EDNS and
  no-EDNS queries through the router and directly to AdGuard. Keep the saved
  configuration as a reference, but do not restore it wholesale during normal
  household use because it contains the earlier DHCP configuration.
- If the fault returns, a clean stock factory reset and manual
  reconfiguration could test for corrupt saved settings. No reset is warranted
  by the successful restoration test alone.
- [OpenWrt supports the R7450](https://openwrt.org/toh/netgear/r6800) and
  publishes a [model-specific factory image](https://downloads.openwrt.org/releases/25.12.6/targets/ramips/mt7621/).
  It uses a different DNS/DHCP implementation and can advertise a separate
  resolver with [DHCP option 6](https://openwrt.org/docs/guide-user/base-system/dhcp_configuration).
  This is a viable firmware migration to plan, not a low-downtime change.
  Standard OpenWrt images [disable Wi-Fi on first boot](https://openwrt.org/docs/guide-quick-start/basic_wifi),
  but a [custom image with first-boot wireless settings](https://openwrt.org/docs/guide-user/installation/flashing_openwrt_with_wifi_enabled_on_first_boot)
  can enable it. A wired client is therefore not an absolute installation
  requirement; it remains the safer flash and recovery path if the custom
  image fails to boot or apply its wireless configuration.
  Record WAN, LAN, Wi-Fi, reservations, and firewall settings; verify the
  downloaded factory image checksum and a stock-firmware recovery route before
  flashing. The saved Netgear configuration is not an OpenWrt configuration.
  Test both cameras' Wi-Fi and streams after any firmware change.
- The R7450 gives DHCP clients its own LAN address as DNS. Its restored
  AdGuard upstream currently answers local and public EDNS lookups through
  that relay. If `lab-core` or Proxmox goes down, check DNS availability as
  part of recovery.
- Both Thingino cameras answered HTTP at `.23` and `.24` after the router
  fallback. Their static-versus-DHCP configuration remains unverified.

## Afternoon recurrence: Proxmox host became unresponsive

At about 15:30 MST, `norman` stopped serving the VM. The last persistent
`lab-core` journal entries are at 15:30:09; Tailscale last saw it at 15:32.
The previous Proxmox journal has no suspend, hibernate, or clean shutdown
event near the outage (its last entry is an ordinary cron job at 15:17).
Proxmox marked that boot as a crash after the forced restart, and journald
reported an unclean journal on the new boot. These records do not establish
whether lid closure, firmware, the kernel, or another fault caused the hang.

At 16:49–16:54, `x1c-g9` joined the home Wi-Fi and confirmed the router at
`.1` was reachable and still served DHCP. A subnet scan found the cameras and
other clients, but neither `norman` at `.200` nor `lab-core` at `.210` responded
to discovery; no other live address exposed Proxmox port 8006. The router's
DNS queries timed out because its AdGuard upstream was unavailable. A brief
power-button press did not restore the laptop's blank screen or LAN presence.

After a forced physical restart, Proxmox booted at 16:56, VM 120 started, and
both AdGuard at `.210` and the router's DNS relay at `.1` answered local and
public queries. The existing `/etc/systemd/logind.conf` already had
`HandleLidSwitch=ignore` and `HandleLidSwitchExternalPower=ignore`; the docked
lid action defaults to `ignore`. To prevent OS-initiated sleep on this
always-on host, `sleep.target`, `suspend.target`, `hibernate.target`,
`hybrid-sleep.target`, and `suspend-then-hibernate.target` were masked and
verified as masked. This does not rule out a firmware or kernel hang when the
lid closes, so a supervised lid-close test was needed before calling the host
stable with the lid closed.

A supervised test followed at 17:01:38–17:02:53: Proxmox logged the lid
closing and reopening, and its ACPI lid state matched. All 45 monitored
samples during the closed interval found Proxmox, `lab-core`, and AdGuard DNS
responsive. No systemd suspend occurred. This verifies a short closed-lid
interval after the sleep-target masks, but does not explain or exclude a
longer-duration or intermittent hang.

On reopening, the local screen was black while SSH, the VM, and DNS continued
working. The eDP display was connected and enabled, but the framebuffer was
blanked (`fb0/blank=1`) and the backlight's actual brightness was zero.
The kernel console's idle blank timer is 60 seconds. Writing `0` to
`/sys/class/graphics/fb0/blank` restored full backlight brightness, and the
user confirmed the login screen was visible and responsive. At that point,
console blanking still had its 60-second setting; the blank screen in this
short test was separate from host sleep. No further crash detail was found in
the available Proxmox journal or crash storage.

### Lid-controlled console display

The user requested the console screen on when the lid is open and off when
closed, without periodic lid polling. An enabled `norman-lid-display.service`
on Proxmox now subscribes to logind's D-Bus property-change events. At
startup it disables the console's idle blank timer with `setterm`, reads the
current `LidClosed` property, and writes the corresponding state to
`/sys/class/graphics/fb0/blank` on each event. The host copies are
`/usr/local/libexec/norman-lid-display.py` and
`/etc/systemd/system/norman-lid-display.service`; the source files are under
`scripts/` in this repository. It does not suspend the host or stop the VM.

The service logged multiple lid close/open transitions at 17:14–17:15.
During a closed interval, framebuffer blank was `1`, actual backlight
brightness was `0`, VM 120 remained running, and the router answered
`lab.adre.me`. On opening, the service logged framebuffer `on`, and the user
confirmed the login screen returned automatically.
