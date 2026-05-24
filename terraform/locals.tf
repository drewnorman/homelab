locals {
  guests = {
    adguard = {
      ip = var.service_ips.adguard_lxc
    }
    edge = {
      ip = var.service_ips.edge_lxc
    }
    homepage = {
      ip = var.service_ips.homepage_lxc
    }
    authelia = {
      ip = var.service_ips.authelia_lxc
    }
    lldap = {
      ip = var.service_ips.lldap_lxc
    }
    jellyfin = {
      ip = var.service_ips.jellyfin_lxc
    }
    arr = {
      ip = var.service_ips.arr_lxc
    }
    qbittorrent_vpn = {
      ip = var.service_ips.qbittorrent_vpn_lxc
    }
  }
}
