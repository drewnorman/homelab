# Router DNS relay and DHCP recovery — 2026-11-06

The household router intermittently delayed or dropped DNS queries while direct queries to the local resolver succeeded. During recovery, an attempted DHCP handoff also changed the LAN path unexpectedly. The original packet timings, device addresses, and host recovery commands are kept in private operational notes.

## Lessons retained

- Test fresh local and public names over UDP, TCP, and EDNS through both the router and the local resolver. A successful cached query does not establish that the relay is healthy.
- Keep exactly one DHCP server active during any handoff. Verify lease address, gateway, resolver, and local name resolution from a client before retiring the old service.
- Maintain local console access and a known good network configuration for the virtualization host. Verify host name mappings and management URLs after an address change.
- Check tailnet credentials and route approval separately from LAN DNS. A failed remote connection does not by itself identify a DNS fault.

The direct resolver path worked in the final checks. The intermittent relay cause was not established, so future network changes should include repeated fresh-query tests.
