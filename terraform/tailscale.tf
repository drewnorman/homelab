resource "tailscale_tailnet_key" "edge" {
  count = var.enable_tailscale_management ? 1 : 0

  reusable      = var.tailscale_auth_key_reusable
  ephemeral     = false
  preauthorized = var.tailscale_auth_key_preauthorized
  expiry        = var.tailscale_auth_key_expiry_seconds
  description   = "${var.homelab_name}-core provisioning key"
}

resource "tailscale_dns_preferences" "magic_dns" {
  count = var.enable_tailscale_management ? 1 : 0

  magic_dns = true
}

resource "tailscale_dns_split_nameservers" "homelab" {
  count = var.enable_tailscale_management ? 1 : 0

  domain      = var.search_domain
  nameservers = [local.tailscale_split_dns_nameserver_ip]
}

# Resource names retain "edge" to preserve Terraform state continuity from the
# old layout. The managed device is lab-core in the single-VM design.
data "tailscale_device" "edge" {
  count = var.enable_tailscale_management && local.tailscale_core_device_management_enabled ? 1 : 0

  hostname = local.core_vm.hostname
  wait_for = "120s"
}

resource "tailscale_device_subnet_routes" "edge" {
  count = var.enable_tailscale_management && local.tailscale_core_device_management_enabled ? 1 : 0

  device_id = data.tailscale_device.edge[0].node_id
  # Expose the consolidated VM and current DNS cutover address through Tailscale.
  routes = local.tailscale_core_routes
}

resource "tailscale_device_key" "edge" {
  count = var.enable_tailscale_management && local.tailscale_core_device_management_enabled ? 1 : 0

  device_id           = data.tailscale_device.edge[0].node_id
  key_expiry_disabled = true
}
