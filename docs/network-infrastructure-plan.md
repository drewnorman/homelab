# Home network build

Status: purchase and deployment plan, November 5, 2026. No hardware or live configuration has been changed by this plan.

## Decision

Keep the Dell XPS laptop (`norman`) as the sole Proxmox host and `lab-core` as its NixOS VM. Put **OPNsense directly on a Protectli VP2430e** for household routing. Use the **Omada SG2210XMP-M2** as a standalone, flat-LAN managed switch. Convert the **Netgear R7450** to AP mode. Preserve Nix/OpenTofu ownership of application services. No Omada controller, second Proxmox host, new AP, or VLAN is needed at cutover.

OPNsense is the gateway choice because its local UI, diagnostics, and configuration restore make handoff and recovery easier. It runs bare metal, as NixOS would. Same-subnet transfers stay on the switch.

## Topology and port map

```text
ISP modem / ONT
  │  ISP Ethernet handoff (speed and bridge/DMZ requirements to verify)
  │  Cat6 patch lead
  ▼
Protectli VP2430e, OPNsense: WAN port / LAN 192.168.1.1
  │  2.5 GbE LAN, Cat6 patch lead
  ▼
Omada SG2210XMP-M2, standalone, all ports untagged LAN initially
  1  gateway LAN
  2  Dell XPS / norman via tested USB 3 2.5 GbE adapter → vmbr0
       └─ lab-core VM 192.168.1.210; norman host 192.168.1.200
  3  Netgear R7450 Internet port, AP mode, 1 GbE → household Wi-Fi/cameras
  4  PS4 (existing cable, device-negotiated speed)
  5  TV (existing cable, device-negotiated speed)
  6–8  spare
  SFP+ 9–10  unused

UPS battery outlets: modem/ONT + gateway + switch + Netgear power supply
  (+ laptop charger if UPS load/runtime allows)
UPS USB data: gateway NUT → Proxmox NUT client over LAN
```

The switch's eight copper ports are 2.5 GbE PoE+ with a **160 W total** budget and two 10 GbE SFP+ slots; it is fanless and desktop/wall mounted, so put it on a ventilated shelf. [Omada specifications](https://www.omadanetworks.com/us/business-networking/omada-switch-access-pro/sg2210xmp-m2/v1/). The Netgear's documented AP setup uses its **Internet port** for the uplink. Keep its radio outside the metal rack, close to its useful current location. [R7450 manual](https://www.downloads.netgear.com/files/GDC/R7450/R7450_UM_EN.pdf).

## Purchase list and physical build

| Item | Selection and reason |
| --- | --- |
| Gateway | [Protectli VP2430e](https://protectli.com/product/vp2430e/), Intel N150 and four Intel I226-V 2.5 GbE ports; 8 GB compatible DDR5 SO-DIMM and a modest 128–256 GB NVMe SSD. Barebones listing was **$419** on November 5; RAM/SSD are extra. Buy compatible parts or a configured unit. Use two NICs; the remaining NICs are not switch ports. |
| Switch | [Omada SG2210XMP-M2](https://store.omadanetworks.com/products/omada-8-port-2-5gbase-t-and-2-port-10ge-sfp-smart-switch-with-8x-poe-160w), listed around **$250–257** when checked. Run standalone with one flat LAN. PoE capacity is reserved for a later AP/camera. |
| Laptop link | One USB 3 2.5 GbE adapter with current Linux support, e.g. [Plugable USBC-E2500](https://plugable.com/products/usbc-e2500); check that the laptop port does not share a bandwidth-limited hub. Retain the old 1 GbE adapter as rollback. |
| UPS | **CyberPower CP1500PFCLCD** as the initial network UPS: 1500 VA / 1000 W, line interactive sine wave, USB status, **$274.95 MSRP**. Put it on a ventilated bottom shelf. It has **six battery-backed outlets**. Its published runtime is **10 minutes at 500 W**; the 10–15 minute target still needs validation at the measured load and with future PoE devices. [CyberPower details](https://www.cyberpowersystems.com/product/ups/pfc-sinewave/cp1500pfclcd/). |
| Rack | Used, open/ventilated, adjustable-depth **four-post 19-inch rack around 12–18U**, anchored as appropriate, with enough depth for shelves and safe cable bends. Check local dimensions, weight, and complete hardware before purchase. The rack is for organization and future growth; the network works without it. |
| Shelf and management | One ventilated rack shelf sized for the gateway/switch and one low shelf for the tower UPS; a small horizontal cable manager and hook-and-loop ties. Keep the laptop ventilated, supported, and accessible. |
| Copper and termination | Buy **Cat6** patch leads for ONT→gateway, gateway→switch, switch→laptop, and switch→AP; choose lengths after measuring the route, with slack. Use solid-conductor in-wall cable and keystone jacks only for permanent runs; use stranded factory patch leads at equipment. Label both ends and record switch port numbers. |
| Patch panel | Optional 8–12-port keystone panel once cables terminate in the rack. For a few direct patch leads it adds no performance or reliability. |
| Power distribution | The UPS has battery outlets for this small build. Add a basic listed rack PDU only if more outlets or tidier distribution is genuinely needed, within UPS and PDU ratings. Plug the UPS directly into the wall, and keep all network power adapters on battery-backed outlets. |

A native rack UPS, such as the [CyberPower CP1500PFCRM2U](https://www.cyberpowersystems.com/product/ups/pfc-sinewave/cp1500pfcrm2u/), is the rack-format alternative: 2U, 1500 VA / 1000 W, listed **$399.95 MSRP**, with a 10.2-minute published runtime at 500 W. That is roughly **$125 more** than the tower model for similar rated capacity, so choose it only if rack integration is worth that premium. A used APC/Eaton is viable only after checking battery age, replacement cost, rails, and local price. Verify UPS USB/NUT compatibility during the return window.

## Software ownership and addresses

| Device | Owner and address | Responsibilities |
| --- | --- | --- |
| OPNsense gateway | Local web UI and encrypted config backup; `192.168.1.1/24` | WAN, NAT/firewall, one DHCP server, Unbound DNS, Tailscale subnet route, UPS monitoring. No public WAN management. |
| Omada switch | Standalone local UI and exported config; reserve a free `192.168.1.x` management address after reviewing leases | One untagged LAN, management from trusted LAN, firmware, port/PoE status. No controller at cutover. |
| Netgear AP | Local UI and saved config; reserve a free management address | Existing SSID/password, radio channels, AP mode. No DHCP, NAT, or routing. |
| `norman` Proxmox | Existing host config; preserve `.200` | `vmbr0` on tested 2.5 GbE adapter, VMs, UPS client and graceful VM/host shutdown. |
| `lab-core` NixOS VM | Nix flake/OpenTofu; preserve `.210` | nginx/TLS and applications, including Home Assistant, Frigate, Jellyfin, and media services. Retain Tailscale as a device, but stop advertising the LAN route. |
| Cameras | Preserve `.23` and `.24` after checking whether each is static or DHCP-reserved | Remain on existing Netgear Wi-Fi and flat LAN initially. |

### DNS migration

Move LAN DNS responsibility off `lab-core`. Configure OPNsense Unbound at `.1` with an A override for `lab.adre.me` and a wildcard host override for `*.lab.adre.me`, both pointing to `.210`, where nginx remains. OPNsense documents wildcard host overrides and DNS blocklists. [Unbound guide](https://docs.opnsense.org/manual/unbound.html). Start with the current explicit blocked domains and one supported blocklist source, then compare representative allowed/blocked queries and latency before adding others. **Do not paste AdGuard filter URLs or rule syntax wholesale:** Unbound's custom blocklist URL format accepts plain FQDN/wildcard-domain lists, while the current AdGuard setup also has native AdGuard rules. Preserve the [current rule inventory](../nix/hosts/core/default.nix) for migration and disable `lab-core` AdGuard only after the gateway answers correctly.

Retire the `adguard.lab.adre.me` / `dns.lab.adre.me` nginx routes and their dashboard health check when AdGuard is removed, and put the OPNsense management URL in the household guide. Do not point those application names at a dead backend. Review any Home Assistant AdGuard integration before removal.

Keep the Proxmox host, VM, clients, and DHCP option 6 pointed at `.1` for local names. The current OpenTofu `dns_servers` default includes public `1.1.1.1`; remove that as a client fallback when internal DNS is moved, since public DNS cannot resolve `lab.adre.me`. Give the gateway reliable upstream DNS and test both LAN and Tailscale resolution. Review the recent DNS latency separately; this hardware change is not evidence that DNS speed will improve.

### Remote access

Install the OPNsense `os-tailscale` community plugin, join the gateway to the tailnet, and advertise `192.168.1.0/24` from it. Keep `lab-core` joined for its own services, but remove `--advertise-routes=192.168.1.0/24` from the Nix config and transfer route approval/management in OpenTofu. Change split DNS for `lab.adre.me` from `.210` to the gateway's **Tailscale IP**, and allow DNS to that interface from the tailnet. This keeps DNS and subnet access available if the laptop is off; application URLs still need `.210`. [Tailscale OPNsense install](https://tailscale.com/docs/install/opnsense), [Tailscale split DNS](https://tailscale.com/docs/reference/dns-in-tailscale). Do not expose gateway or switch management to the public WAN.

### UPS and recovery

Connect UPS USB to the gateway. Configure OPNsense `os-nut` as the UPS server with its USB HID driver, restricted to the trusted LAN, and configure Proxmox as a NUT secondary/client. Validate the exact UPS/driver combination and shutdown behavior on battery before relying on it. On a prolonged outage, Proxmox should stop VMs and then the host; OPNsense should remain powered long enough for that and shut down only near the tested battery threshold. The laptop's internal battery is extra protection, but verify its condition and Proxmox response to AC loss. [OPNsense NUT plugin](https://docs.opnsense.org/manual/how-tos/nut.html), [NUT shutdown roles](https://networkupstools.org/docs/man/nut.html).

Keep an encrypted OPNsense config backup **off the laptop**, plus switch and Netgear backups, port map, credentials in the household password manager, and a one-page recovery guide. It should show the first checks: UPS/display, ONT lights, gateway WAN/DNS, switch port lights, and Netgear AP; it should also show how to restore the saved Netgear router setup if the Protectli fails. OPNsense supports configuration restore. [Backup guide](https://docs.opnsense.org/manual/backups.html).

## Cutover sequence and acceptance

1. **Inventory.** Record ISP handoff (DHCP/PPPoE, VLAN, bridge/DMZ, IPv6), current Netgear WAN and DHCP settings/reservations, Wi-Fi SSID/password/channel, cable routes, and occupied IPs. Export its configuration. Verify rack space and outlet placement; measure current load where possible.
2. **Build the physical LAN under the old router.** Install the switch behind the still-routing Netgear as an untagged switch. Label leads. Put the Netgear radio outside the rack. Test the 2.5 GbE laptop adapter and local-console recovery before moving `vmbr0`; confirm a negotiated 2.5 GbE link, VM connectivity, and stable sustained transfer. Keep the 1 GbE adapter ready.
3. **Prepare OPNsense isolated.** Install it on Protectli, update firmware, assign verified physical WAN/LAN ports, set `.1`, DHCP, Unbound, firewall, management credentials, Tailscale, NUT, and encrypted backup. Test WAN and DNS behind the current router or with an isolated client. Never connect two active DHCP servers to the production LAN.
4. **Cut over in one local maintenance window.** Move ISP handoff to Protectli WAN, Protectli LAN to switch port 1, and convert Netgear to AP mode on its Internet port at switch port 3. Preserve `.1`, `.200`, `.210`, and existing Wi-Fi credentials where practical. Reboot or renew leases only as needed. Verify WAN public IP/double-NAT status and native IPv6 before enabling any IPv6 LAN policy.
5. **Migrate services.** Test public and local DNS, wildcard app names, DHCP reservations, nginx apps, camera streams/Frigate, TV/PS4, and remote tailnet access. Then transfer Tailscale subnet route and split DNS, remove `lab-core`'s route advertisement/AdGuard listener, and retire its AdGuard nginx/dashboard entries. Test again with the laptop deliberately offline: ordinary internet, gateway DNS, and gateway Tailscale access should work, while app URLs on `.210` will be unavailable.
6. **Test outage and recovery.** On a controlled UPS battery test, confirm the ONT/gateway/switch/AP stay up and Proxmox VMs/host shut down before the gateway. Test restart after AC returns, backups, and the written Netgear fallback. Recheck camera packet loss and RTSP stalls against the [existing baseline](thingino-rtsp-stability-2026-10-31.md); the Netgear radio remains the same, so network hardware alone does not promise a camera fix.

Rollback: restore the saved Netgear routing configuration and original ISP/LAN connections; return the switch to the untagged layout and restore the old `lab-core` Tailscale/DNS ownership if already transferred. A bad 2.5 GbE adapter or `vmbr0` change is rolled back at the laptop console to the old adapter.

## Value order

1. **Immediate continuity and serviceability:** dedicated gateway plus Unbound/DHCP off the laptop, a short recovery guide and backups, and a modest UPS for the network. A laptop outage then no longer takes household DNS and remote subnet access down; brief power flickers should not reboot the network. The current Netgear already routes independently of the laptop. ISP equipment upstream may still go offline during a wider outage.
2. **Useful foundation:** managed 2.5 GbE switch and a tested laptop adapter. Port visibility, future PoE/VLAN support, and 2.5 GbE headroom are real. Today's Wi-Fi AP and most clients remain at 1 GbE or less, and there is only one planned 2.5 GbE LAN endpoint besides the gateway, so immediate transfer gains may be small.
3. **Organization and later expansion:** used rack, shelves, optional patch panel/PDU, native rack UPS, dedicated PoE AP, camera/IoT VLANs, and 10 GbE SFP+ links. Buy these when placement, cable runs, measured power load, or a second fast endpoint gives them a concrete payoff. A VLAN-capable AP is needed before wireless cameras can be separated by SSID/VLAN; the current Netgear is kept for the initial flat network.
