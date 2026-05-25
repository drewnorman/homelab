resource "tailscale_tailnet_key" "edge" {
  count = var.enable_tailscale_management ? 1 : 0

  reusable      = var.tailscale_auth_key_reusable
  ephemeral     = false
  preauthorized = var.tailscale_auth_key_preauthorized
  expiry        = var.tailscale_auth_key_expiry_seconds
  description   = "${var.homelab_name}-edge provisioning key"
}

resource "tailscale_dns_preferences" "magic_dns" {
  count = var.enable_tailscale_management ? 1 : 0

  magic_dns = true
}

resource "tailscale_dns_split_nameservers" "homelab" {
  count = var.enable_tailscale_management ? 1 : 0

  domain      = var.search_domain
  nameservers = [local.guests.adguard.ip]
}

data "tailscale_device" "edge" {
  count = var.enable_tailscale_management && var.enable_tailscale_edge_device_management ? 1 : 0

  hostname = "${var.homelab_name}-edge"
  wait_for = "120s"
}

resource "tailscale_device_subnet_routes" "edge" {
  count = var.enable_tailscale_management && var.enable_tailscale_edge_device_management ? 1 : 0

  device_id = data.tailscale_device.edge[0].node_id
  # Expose key services through the edge Tailscale node.
  # Each NixOS host also runs its own Tailscale daemon (via common.nix),
  # so hosts are individually reachable; these routes cover services that
  # don't join the tailnet themselves.
  routes = [
    "${local.guests.adguard.ip}/32",
    "${local.guests.edge.ip}/32",
    "${local.guests.jellyfin.ip}/32",
  ]
}

resource "tailscale_device_key" "edge" {
  count = var.enable_tailscale_management && var.enable_tailscale_edge_device_management ? 1 : 0

  device_id           = data.tailscale_device.edge[0].node_id
  key_expiry_disabled = true
}
