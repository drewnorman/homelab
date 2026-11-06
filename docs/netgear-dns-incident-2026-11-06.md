# Netgear DNS relay and DHCP recovery — 2026-11-06

Times are America/Denver (MST). This records the live fallback; it is not a
claim that the router DNS relay is fixed.

## Agent handoff

- Last verified: `StorminNorman` gave `x1c-g9` a 24-hour router DHCP lease
  `192.168.1.111/24` at 10:05 MST; gateway/DNS were `192.168.1.1`. Ping to
  router and `1.1.1.1`, a normal lookup, and HTTPS succeeded. The user said
  Wi-Fi seemed to work and chose to defer Proxmox troubleshooting.
- Router DNS remains faulty for UDP EDNS queries. UDP without EDNS and TCP
  answer; direct `1.1.1.1` answers. Do not interpret working HTTPS as proof
  that every client's DNS is reliable.
- Router DHCP is active on `.100–.199`; its WAN DNS is `1.1.1.1`/`1.0.0.1`.
- `norman` and `lab-core` returned at `.200`/`.210`. Proxmox's `vmbr0` was
  already on `.200`, but `/etc/hosts` still mapped `norman` to `.50`, causing
  the console banner to advertise the wrong URL. The host mapping was fixed,
  the banner refreshed, and the Proxmox web page answered at `.200:8006`.
- The first Nix deploy rolled back after the saved Tailscale auth key failed.
  The Tailscale API and VM auth keys were renewed; the guarded deploy then
  succeeded. AdGuard DHCP remained disabled after a service restart. It does
  not listen on UDP 67, while DNS answers on `.210:53`.
- `README.md` and this note document the fallback. The unrelated untracked
  `docs/network-infrastructure-plan.md` belongs to another task; leave it alone.
- The user is weighing OpenWrt. R7450 support and a model-specific factory
  image are published. Firmware Selector can embed first-boot wireless
  settings, so wired access is not an absolute requirement; it remains the
  safer flash/recovery path. No stock reset or firmware flash was performed.
  Both cameras answered HTTP at `.23` and `.24`, but their address mode is
  unverified; revisit them after the router decision.

## Current LAN state

- Netgear R7450 LAN IP/gateway: `192.168.1.1/24`.
- Router WAN DNS: `1.1.1.1`, then `1.0.0.1`.
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
`/home/drew/downloads/NETGEAR_R7450.cfg` before the WAN DNS change. Applying
that change unexpectedly moved the router LAN to `10.0.0.1/24`, with DHCP
still off. Its WAN `100.104.18.55/19` did not overlap the original LAN.
The cause of the LAN change is unknown. The router LAN was restored to
`192.168.1.1/24` without a factory reset.

At 10:05 MST, `x1c-g9` acquired `192.168.1.111/24` from `192.168.1.1`, with
gateway and DNS both `192.168.1.1`. Router ping, public `1.1.1.1` ping, a
normal system lookup, and HTTPS to `www.example.com` succeeded. This verifies
basic internet use on that client, not every household device or every DNS
query.

## DNS relay evidence

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

The evidence points to the router's handling of incoming UDP EDNS queries;
the exact firmware defect is not known. The installed firmware is
`V1.2.1.92_1.0.1`, matching [NETGEAR's R7450 1.2.1.92 release](https://kb.netgear.com/000066523/R7450-Firmware-Version-1-2-1-92).
The [R7450 manual](https://www.downloads.netgear.com/files/GDC/R7450/R7450_UM_EN.pdf)
says its DHCP service gives clients the router's LAN address as DNS.

## Remaining checks

- A clean stock factory reset and manual reconfiguration could rule out a
  corrupt saved setting, but it keeps the same DNS implementation. Restoring
  the saved configuration wholesale would not isolate configuration state.
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
- Until the DNS relay is repaired or bypassed, some clients may retry DNS
  without EDNS or use TCP, causing slow lookups despite working DHCP.
- The R7450 gives DHCP clients its own LAN address as DNS. Pointing its
  upstream DNS to AdGuard at `.210` may help local name lookups, but it would
  still use the router's relay, which timed out for EDNS queries after upstream
  DNS was changed to public resolvers. A direct query to AdGuard answered.
  No router DNS change to `.210` has been made; test it in a controlled window.
- Both Thingino cameras answered HTTP at `.23` and `.24` after the router
  fallback. Their static-versus-DHCP configuration remains unverified.
