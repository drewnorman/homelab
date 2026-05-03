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
  }

  docker_inventory = var.enable_docker_host ? trimspace(<<-EOT
    [docker]
    ${proxmox_virtual_environment_vm.docker_host[0].name} ansible_host=${local.guests.docker.ip} ansible_user=${var.vm_ci_user}
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
    <<-EOT
    [media]
    ${var.homelab_name}-jellyfin ansible_host=${local.guests.jellyfin.ip} ansible_user=root
    EOT
  ])))
}
