# Home network migration principles

This is a future migration plan, not a record of deployed equipment. The detailed household topology, port map, purchase list, and recovery notes are kept in private operational notes.

## Intended architecture

Use a dedicated gateway for WAN routing, DHCP, DNS, firewalling, and remote subnet access. Keep application services on the existing virtualization host. Place a managed switch between the gateway and wired clients, and run the existing wireless router as an access point during the first cutover. Do not expose management interfaces to the public WAN.

## Cutover and verification

1. Inventory current WAN settings, DHCP reservations, Wi-Fi settings, cabling, and device addresses. Export configuration backups before changing anything.
2. Prepare and test the new gateway on an isolated network. Confirm WAN, DHCP, DNS, firewall, remote access, and recovery access before connecting it to the production LAN.
3. Cut over in one local maintenance window with only one active DHCP server. Preserve the existing network path as a rollback option.
4. Verify internet access, local DNS names, application routes, camera streams, and remote access from the intended clients. Test with the virtualization host offline to confirm the gateway still provides basic network services.
5. Test UPS shutdown behavior and restore from the saved gateway backup. Keep the exact recovery sequence in private notes.

The public NixOS and OpenTofu configuration documents the current application deployment. Operational details that identify household devices or physical port placement belong in private notes.
