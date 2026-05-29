locals {
  core_vm = {
    hostname = "${var.homelab_name}-core"
    ip       = var.core_vm_ip
    vm_id    = var.core_vm_id
  }

  tailscale_core_device_management_enabled = (
    var.enable_tailscale_core_device_management
  )

  tailscale_split_dns_nameserver_ip = coalesce(
    var.tailscale_split_dns_nameserver_ip,
    local.core_vm.ip,
  )

  tailscale_core_routes = distinct([
    "${local.core_vm.ip}/32",
  ])
}
