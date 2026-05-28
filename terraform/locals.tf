locals {
  core_vm = {
    hostname = "${var.homelab_name}-core"
    ip       = var.core_vm_ip
    vm_id    = var.core_vm_id
  }

  tailscale_core_device_management_enabled = (
    var.enable_tailscale_core_device_management ||
    var.enable_tailscale_edge_device_management
  )

  tailscale_split_dns_nameserver_ip = coalesce(
    var.tailscale_split_dns_nameserver_ip,
    var.enable_core_vm ? local.core_vm.ip : var.service_ips.adguard_lxc,
  )

  tailscale_core_routes = distinct([
    "${local.core_vm.ip}/32",
    "${var.service_ips.adguard_lxc}/32",
  ])

  guests = {
    adguard = {
      ip    = var.service_ips.adguard_lxc
      vm_id = var.service_vmids.adguard_lxc
    }
    edge = {
      ip    = var.service_ips.edge_lxc
      vm_id = var.service_vmids.edge_lxc
    }
    monitoring = {
      ip    = var.service_ips.monitoring_lxc
      vm_id = var.service_vmids.monitoring_lxc
    }
    authelia = {
      ip    = var.service_ips.authelia_lxc
      vm_id = var.service_vmids.authelia_lxc
    }
    lldap = {
      ip    = var.service_ips.lldap_lxc
      vm_id = var.service_vmids.lldap_lxc
    }
    jellyfin = {
      ip    = var.service_ips.jellyfin_lxc
      vm_id = var.service_vmids.jellyfin_lxc
    }
    arr = {
      ip    = var.service_ips.arr_lxc
      vm_id = var.service_vmids.arr_lxc
    }
    qbittorrent = {
      ip    = var.service_ips.qbittorrent_lxc
      vm_id = var.service_vmids.qbittorrent_lxc
    }
  }
}
