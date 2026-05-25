locals {
  guests = {
    adguard = {
      ip    = var.service_ips.adguard_lxc
      vm_id = var.service_vmids.adguard_lxc
    }
    edge = {
      ip    = var.service_ips.edge_lxc
      vm_id = var.service_vmids.edge_lxc
    }
    homepage = {
      ip    = var.service_ips.homepage_lxc
      vm_id = var.service_vmids.homepage_lxc
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
