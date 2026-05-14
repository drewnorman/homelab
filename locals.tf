locals {
  guests = {
    adguard = {
      role = "adguard"
      ip   = var.service_ips.adguard_lxc
    }
    edge = {
      role = "edge"
      ip   = var.service_ips.edge_lxc
    }
    docker = {
      role = "docker"
      ip   = var.service_ips.docker_host_vm
    }
    jellyfin = {
      role = "jellyfin"
      ip   = var.service_ips.jellyfin_lxc
    }
    arr = {
      role = "arr"
      ip   = var.service_ips.arr_lxc
    }
    qbittorrent_vpn = {
      role = "qbittorrent_vpn"
      ip   = var.service_ips.qbittorrent_vpn_lxc
    }
    nix = {
      role = "nix"
      ip   = var.service_ips.nix_host_lxc
    }
  }

  docker_inventory = var.enable_docker_host ? trimspace(<<-EOT
    [docker]
    ${proxmox_virtual_environment_vm.docker_host[0].name} ansible_host=${local.guests.docker.ip} ansible_user=${var.vm_ci_user}
  EOT
  ) : ""

  arr_inventory = var.enable_arr_stack ? trimspace(<<-EOT
    [arr]
    ${var.homelab_name}-arr ansible_host=${local.guests.arr.ip} ansible_user=root
  EOT
  ) : ""

  qbittorrent_vpn_inventory = var.enable_qbittorrent_vpn ? trimspace(<<-EOT
    [qbittorrent_vpn]
    ${var.homelab_name}-qbittorrent-vpn ansible_host=${local.guests.qbittorrent_vpn.ip} ansible_user=root
  EOT
  ) : ""

  nix_inventory = var.enable_nix_host ? trimspace(<<-EOT
    [nix]
    ${var.homelab_name}-nix ansible_host=nix.${var.search_domain} ansible_user=${var.vm_ci_user}
  EOT
  ) : ""

  ansible_inventory = trimspace(join("\n\n", compact([
    <<-EOT
    [adguard]
    ${var.homelab_name}-adguard ansible_host=${local.guests.adguard.ip} ansible_user=root
    EOT
    ,
    <<-EOT
    [edge]
    ${var.homelab_name}-edge ansible_host=${local.guests.edge.ip} ansible_user=root
    EOT
    ,
    local.docker_inventory,
    local.arr_inventory,
    local.qbittorrent_vpn_inventory,
    local.nix_inventory,
    <<-EOT
    [media]
    ${var.homelab_name}-jellyfin ansible_host=${local.guests.jellyfin.ip} ansible_user=root
    EOT
  ])))
}
