resource "proxmox_virtual_environment_container" "adguard" {
  node_name     = var.proxmox_node_name
  description   = "AdGuard Home container managed by OpenTofu"
  start_on_boot = true
  started       = true
  tags          = ["adguard", "homelab"]
  unprivileged  = true

  cpu {
    cores = 1
  }

  memory {
    dedicated = 512
    swap      = 512
  }

  disk {
    datastore_id = var.lxc_storage
    size         = 8
  }

  features {
    nesting = true
  }

  initialization {
    hostname = "${var.homelab_name}-adguard"

    dns {
      domain  = var.search_domain
      servers = var.dns_servers
    }

    ip_config {
      ipv4 {
        address = "${local.guests.adguard.ip}/${var.network_cidr}"
        gateway = var.network_gateway
      }
    }

    user_account {
      keys = [trimspace(var.ssh_public_key)]
    }
  }

  network_interface {
    name   = "veth0"
    bridge = var.network_bridge
  }

  operating_system {
    template_file_id = var.lxc_template_file_id
    type             = var.lxc_os_type
  }
}

resource "proxmox_virtual_environment_container" "edge" {
  node_name     = var.proxmox_node_name
  description   = "Reverse proxy and DDNS container managed by OpenTofu"
  start_on_boot = true
  started       = true
  tags          = ["edge", "homelab", "proxy"]
  unprivileged  = true

  cpu {
    cores = 1
  }

  memory {
    dedicated = 768
    swap      = 512
  }

  disk {
    datastore_id = var.lxc_storage
    size         = 8
  }

  initialization {
    hostname = "${var.homelab_name}-edge"

    dns {
      domain  = var.search_domain
      servers = var.dns_servers
    }

    ip_config {
      ipv4 {
        address = "${local.guests.edge.ip}/${var.network_cidr}"
        gateway = var.network_gateway
      }
    }

    user_account {
      keys = [trimspace(var.ssh_public_key)]
    }
  }

  network_interface {
    name   = "veth0"
    bridge = var.network_bridge
  }

  operating_system {
    template_file_id = var.lxc_template_file_id
    type             = var.lxc_os_type
  }
}

resource "proxmox_virtual_environment_container" "homepage" {
  node_name     = var.proxmox_node_name
  description   = "Homepage dashboard container managed by OpenTofu"
  start_on_boot = true
  started       = true
  tags          = ["homelab", "homepage"]
  unprivileged  = true

  cpu {
    cores = 1
  }

  memory {
    dedicated = 1024
    swap      = 512
  }

  disk {
    datastore_id = var.lxc_storage
    size         = 4
  }

  features {
    nesting = true
  }

  initialization {
    hostname = "${var.homelab_name}-homepage"

    dns {
      domain  = var.search_domain
      servers = var.dns_servers
    }

    ip_config {
      ipv4 {
        address = "${local.guests.homepage.ip}/${var.network_cidr}"
        gateway = var.network_gateway
      }
    }

    user_account {
      keys = [trimspace(var.ssh_public_key)]
    }
  }

  network_interface {
    name   = "veth0"
    bridge = var.network_bridge
  }

  operating_system {
    template_file_id = var.lxc_template_file_id
    type             = var.lxc_os_type
  }
}

resource "proxmox_virtual_environment_container" "nix_host" {
  count = var.enable_nix_host ? 1 : 0

  node_name     = var.proxmox_node_name
  description   = "NixOS lab container managed by OpenTofu; built from ${var.nix_config_repo_url}#${var.nix_config_flake_host}"
  start_on_boot = true
  started       = true
  tags          = ["homelab", "nix", "nixos"]
  unprivileged  = true

  cpu {
    cores = var.nix_host_lxc_resources.cores
  }

  memory {
    dedicated = var.nix_host_lxc_resources.memory_mb
    swap      = var.nix_host_lxc_resources.swap_mb
  }

  disk {
    datastore_id = var.lxc_storage
    size         = var.nix_host_lxc_resources.disk_size_gb
  }

  features {
    nesting = true
  }

  initialization {
    hostname = "${var.homelab_name}-nix"
    dns {
      domain  = var.search_domain
      servers = var.dns_servers
    }

    ip_config {
      ipv4 {
        address = "${local.guests.nix.ip}/${var.network_cidr}"
        gateway = var.network_gateway
      }
    }

    user_account {
      keys = [trimspace(var.ssh_public_key)]
    }
  }

  network_interface {
    name   = "veth0"
    bridge = var.network_bridge
  }

  operating_system {
    template_file_id = var.nix_lxc_template_file_id
    type             = var.nix_lxc_os_type
  }

  depends_on = [
    proxmox_download_file.nixos_lxc_template,
  ]
}

resource "proxmox_virtual_environment_container" "arr" {
  count = var.enable_arr_stack ? 1 : 0

  node_name     = var.proxmox_node_name
  description   = "Media automation container (Radarr, Sonarr, Prowlarr) managed by OpenTofu"
  start_on_boot = true
  started       = true
  tags          = ["arr", "homelab", "media"]
  unprivileged  = true

  cpu {
    cores = 2
  }

  memory {
    dedicated = 2048
    swap      = 512
  }

  disk {
    datastore_id = var.lxc_storage
    size         = 8
  }

  dynamic "mount_point" {
    for_each = var.arr_downloads_bind_mount_host_path == null ? [] : [var.arr_downloads_bind_mount_host_path]
    content {
      path   = "/srv/downloads"
      volume = mount_point.value
    }
  }

  dynamic "mount_point" {
    for_each = var.arr_media_bind_mount_host_path == null ? [] : [var.arr_media_bind_mount_host_path]
    content {
      path   = "/mnt/media"
      volume = mount_point.value
    }
  }

  initialization {
    hostname = "${var.homelab_name}-arr"

    dns {
      domain  = var.search_domain
      servers = var.dns_servers
    }

    ip_config {
      ipv4 {
        address = "${local.guests.arr.ip}/${var.network_cidr}"
        gateway = var.network_gateway
      }
    }

    user_account {
      keys = [trimspace(var.ssh_public_key)]
    }
  }

  network_interface {
    name   = "veth0"
    bridge = var.network_bridge
  }

  operating_system {
    template_file_id = var.lxc_template_file_id
    type             = var.lxc_os_type
  }
}

resource "proxmox_virtual_environment_container" "qbittorrent_vpn" {
  count = var.enable_qbittorrent_vpn ? 1 : 0

  node_name     = var.proxmox_node_name
  description   = "qBittorrent container with Proton VPN routing managed by OpenTofu"
  start_on_boot = true
  started       = true
  tags          = ["homelab", "media", "qbittorrent", "vpn"]
  unprivileged  = true

  cpu {
    cores = 1
  }

  memory {
    dedicated = 1024
    swap      = 512
  }

  disk {
    datastore_id = var.lxc_storage
    size         = 8
  }

  dynamic "mount_point" {
    for_each = var.arr_media_bind_mount_host_path == null ? [] : [var.arr_media_bind_mount_host_path]
    content {
      path   = "/mnt/media"
      volume = mount_point.value
    }
  }

  initialization {
    hostname = "${var.homelab_name}-qbittorrent-vpn"

    dns {
      domain  = var.search_domain
      servers = var.dns_servers
    }

    ip_config {
      ipv4 {
        address = "${local.guests.qbittorrent_vpn.ip}/${var.network_cidr}"
        gateway = var.network_gateway
      }
    }

    user_account {
      keys = [trimspace(var.ssh_public_key)]
    }
  }

  network_interface {
    name   = "veth0"
    bridge = var.network_bridge
  }

  operating_system {
    template_file_id = var.lxc_template_file_id
    type             = var.lxc_os_type
  }
}

resource "proxmox_virtual_environment_container" "jellyfin" {
  node_name     = var.proxmox_node_name
  description   = "Lean Jellyfin container managed by OpenTofu"
  start_on_boot = true
  started       = true
  tags          = ["homelab", "jellyfin", "media"]
  unprivileged  = true

  cpu {
    cores = 2
  }

  memory {
    dedicated = 2048
    swap      = 512
  }

  disk {
    datastore_id = var.lxc_storage
    size         = var.jellyfin_lxc_disk_size_gb
  }

  initialization {
    hostname = "${var.homelab_name}-jellyfin"

    dns {
      domain  = var.search_domain
      servers = var.dns_servers
    }

    ip_config {
      ipv4 {
        address = "${local.guests.jellyfin.ip}/${var.network_cidr}"
        gateway = var.network_gateway
      }
    }

    user_account {
      keys = [trimspace(var.ssh_public_key)]
    }
  }

  dynamic "mount_point" {
    for_each = var.jellyfin_media_bind_mount_host_path == null ? [] : [var.jellyfin_media_bind_mount_host_path]

    content {
      path   = "/mnt/media"
      volume = mount_point.value
    }
  }

  network_interface {
    name   = "veth0"
    bridge = var.network_bridge
  }

  operating_system {
    template_file_id = var.lxc_template_file_id
    type             = var.lxc_os_type
  }

  lifecycle {
    ignore_changes = [
      initialization[0].user_account,
      operating_system[0].template_file_id,
    ]
  }
}
