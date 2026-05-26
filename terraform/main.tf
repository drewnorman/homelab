# All containers run NixOS. Terraform provisions the LXC and injects the SSH
# key; subsequent configuration is handled by the NixOS flake via deploy-rs.
#
# After `tofu apply`, bootstrap each host:
#   deploy-rs: deploy .#<host>
# or for a fresh container that hasn't had nixos-rebuild run yet:
#   nixos-rebuild switch --flake .#<host> --target-host root@<ip>

locals {
  lxc_template_depends = var.manage_lxc_template ? [proxmox_download_file.nixos_lxc_template[0]] : []

  lxc_common = {
    node_name     = var.proxmox_node_name
    start_on_boot = true
    started       = true
    unprivileged  = true
  }

  lxc_network = {
    name   = "veth0"
    bridge = var.network_bridge
  }

  lxc_os = {
    template_file_id = var.lxc_template_file_id
    type             = "nixos"
  }

  lxc_dns = {
    domain  = var.search_domain
    servers = var.dns_servers
  }
}

# ---------------------------------------------------------------------------
# AdGuard Home — DNS + ad blocking
# ---------------------------------------------------------------------------

resource "proxmox_virtual_environment_container" "adguard" {
  vm_id         = local.guests.adguard.vm_id
  node_name     = local.lxc_common.node_name
  description   = "AdGuard Home — managed by NixOS flake"
  start_on_boot = local.lxc_common.start_on_boot
  started       = local.lxc_common.started
  unprivileged  = local.lxc_common.unprivileged
  tags          = ["adguard", "homelab", "nixos"]

  cpu { cores = var.lxc_resources.adguard.cores }
  memory {
    dedicated = var.lxc_resources.adguard.memory_mb
    swap      = var.lxc_resources.adguard.swap_mb
  }
  disk {
    datastore_id = var.lxc_storage
    size         = var.lxc_resources.adguard.disk_gb
  }
  features { nesting = true }
  device_passthrough {
    path = "/dev/net/tun"
    gid  = 0
    uid  = 0
  }

  initialization {
    hostname = "${var.homelab_name}-adguard"
    dns {
      domain  = local.lxc_dns.domain
      servers = local.lxc_dns.servers
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
    name   = local.lxc_network.name
    bridge = local.lxc_network.bridge
  }

  operating_system {
    template_file_id = local.lxc_os.template_file_id
    type             = local.lxc_os.type
  }

  lifecycle {
    ignore_changes = [
      initialization[0].user_account,
    ]
  }

  depends_on = [proxmox_download_file.nixos_lxc_template]
}

# ---------------------------------------------------------------------------
# Edge — nginx reverse proxy + ACME TLS
# ---------------------------------------------------------------------------

resource "proxmox_virtual_environment_container" "edge" {
  vm_id         = local.guests.edge.vm_id
  node_name     = local.lxc_common.node_name
  description   = "Edge reverse proxy — managed by NixOS flake"
  start_on_boot = local.lxc_common.start_on_boot
  started       = local.lxc_common.started
  unprivileged  = local.lxc_common.unprivileged
  tags          = ["edge", "homelab", "nixos", "proxy"]

  cpu { cores = var.lxc_resources.edge.cores }
  memory {
    dedicated = var.lxc_resources.edge.memory_mb
    swap      = var.lxc_resources.edge.swap_mb
  }
  disk {
    datastore_id = var.lxc_storage
    size         = var.lxc_resources.edge.disk_gb
  }
  features { nesting = true }
  device_passthrough {
    path = "/dev/net/tun"
    gid  = 0
    uid  = 0
  }

  initialization {
    hostname = "${var.homelab_name}-edge"
    dns {
      domain  = local.lxc_dns.domain
      servers = local.lxc_dns.servers
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
    name   = local.lxc_network.name
    bridge = local.lxc_network.bridge
  }

  operating_system {
    template_file_id = local.lxc_os.template_file_id
    type             = local.lxc_os.type
  }

  lifecycle {
    ignore_changes = [
      initialization[0].user_account,
    ]
  }

  depends_on = [proxmox_download_file.nixos_lxc_template]
}

# ---------------------------------------------------------------------------
# Homepage — dashboard
# ---------------------------------------------------------------------------

resource "proxmox_virtual_environment_container" "homepage" {
  vm_id         = local.guests.homepage.vm_id
  node_name     = local.lxc_common.node_name
  description   = "Homepage dashboard — managed by NixOS flake"
  start_on_boot = local.lxc_common.start_on_boot
  started       = local.lxc_common.started
  unprivileged  = local.lxc_common.unprivileged
  tags          = ["homelab", "homepage", "nixos"]

  cpu { cores = var.lxc_resources.homepage.cores }
  memory {
    dedicated = var.lxc_resources.homepage.memory_mb
    swap      = var.lxc_resources.homepage.swap_mb
  }
  disk {
    datastore_id = var.lxc_storage
    size         = var.lxc_resources.homepage.disk_gb
  }
  features { nesting = true }
  device_passthrough {
    path = "/dev/net/tun"
    gid  = 0
    uid  = 0
  }

  initialization {
    hostname = "${var.homelab_name}-homepage"
    dns {
      domain  = local.lxc_dns.domain
      servers = local.lxc_dns.servers
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
    name   = local.lxc_network.name
    bridge = local.lxc_network.bridge
  }

  operating_system {
    template_file_id = local.lxc_os.template_file_id
    type             = local.lxc_os.type
  }

  lifecycle {
    ignore_changes = [
      initialization[0].user_account,
    ]
  }

  depends_on = [proxmox_download_file.nixos_lxc_template]
}

# ---------------------------------------------------------------------------
# Authelia — SSO / forward auth
# ---------------------------------------------------------------------------

resource "proxmox_virtual_environment_container" "authelia" {
  vm_id         = local.guests.authelia.vm_id
  node_name     = local.lxc_common.node_name
  description   = "Authelia SSO — managed by NixOS flake"
  start_on_boot = local.lxc_common.start_on_boot
  started       = local.lxc_common.started
  unprivileged  = local.lxc_common.unprivileged
  tags          = ["authelia", "homelab", "nixos"]

  cpu { cores = var.lxc_resources.authelia.cores }
  memory {
    dedicated = var.lxc_resources.authelia.memory_mb
    swap      = var.lxc_resources.authelia.swap_mb
  }
  disk {
    datastore_id = var.lxc_storage
    size         = var.lxc_resources.authelia.disk_gb
  }
  features { nesting = true }
  device_passthrough {
    path = "/dev/net/tun"
    gid  = 0
    uid  = 0
  }

  initialization {
    hostname = "${var.homelab_name}-authelia"
    dns {
      domain  = local.lxc_dns.domain
      servers = local.lxc_dns.servers
    }
    ip_config {
      ipv4 {
        address = "${local.guests.authelia.ip}/${var.network_cidr}"
        gateway = var.network_gateway
      }
    }
    user_account {
      keys = [trimspace(var.ssh_public_key)]
    }
  }

  network_interface {
    name   = local.lxc_network.name
    bridge = local.lxc_network.bridge
  }

  operating_system {
    template_file_id = local.lxc_os.template_file_id
    type             = local.lxc_os.type
  }

  lifecycle {
    ignore_changes = [
      initialization[0].user_account,
    ]
  }

  depends_on = [proxmox_download_file.nixos_lxc_template]
}

# ---------------------------------------------------------------------------
# LLDAP — lightweight LDAP user directory
# ---------------------------------------------------------------------------

resource "proxmox_virtual_environment_container" "lldap" {
  vm_id         = local.guests.lldap.vm_id
  node_name     = local.lxc_common.node_name
  description   = "LLDAP user directory — managed by NixOS flake"
  start_on_boot = local.lxc_common.start_on_boot
  started       = local.lxc_common.started
  unprivileged  = local.lxc_common.unprivileged
  tags          = ["homelab", "lldap", "nixos"]

  cpu { cores = var.lxc_resources.lldap.cores }
  memory {
    dedicated = var.lxc_resources.lldap.memory_mb
    swap      = var.lxc_resources.lldap.swap_mb
  }
  disk {
    datastore_id = var.lxc_storage
    size         = var.lxc_resources.lldap.disk_gb
  }
  features { nesting = true }
  device_passthrough {
    path = "/dev/net/tun"
    gid  = 0
    uid  = 0
  }

  initialization {
    hostname = "${var.homelab_name}-lldap"
    dns {
      domain  = local.lxc_dns.domain
      servers = local.lxc_dns.servers
    }
    ip_config {
      ipv4 {
        address = "${local.guests.lldap.ip}/${var.network_cidr}"
        gateway = var.network_gateway
      }
    }
    user_account {
      keys = [trimspace(var.ssh_public_key)]
    }
  }

  network_interface {
    name   = local.lxc_network.name
    bridge = local.lxc_network.bridge
  }

  operating_system {
    template_file_id = local.lxc_os.template_file_id
    type             = local.lxc_os.type
  }

  lifecycle {
    ignore_changes = [
      initialization[0].user_account,
    ]
  }

  depends_on = [proxmox_download_file.nixos_lxc_template]
}

# ---------------------------------------------------------------------------
# Jellyfin — media server
# ---------------------------------------------------------------------------

resource "proxmox_virtual_environment_container" "jellyfin" {
  vm_id         = local.guests.jellyfin.vm_id
  node_name     = local.lxc_common.node_name
  description   = "Jellyfin media server — managed by NixOS flake"
  start_on_boot = local.lxc_common.start_on_boot
  started       = local.lxc_common.started
  unprivileged  = local.lxc_common.unprivileged
  tags          = ["homelab", "jellyfin", "media", "nixos"]

  cpu { cores = var.lxc_resources.jellyfin.cores }
  memory {
    dedicated = var.lxc_resources.jellyfin.memory_mb
    swap      = var.lxc_resources.jellyfin.swap_mb
  }
  disk {
    datastore_id = var.lxc_storage
    size         = coalesce(var.jellyfin_lxc_disk_size_gb, var.lxc_resources.jellyfin.disk_gb)
  }
  features { nesting = true }
  device_passthrough {
    path = "/dev/net/tun"
    gid  = 0
    uid  = 0
  }

  initialization {
    hostname = "${var.homelab_name}-jellyfin"
    dns {
      domain  = local.lxc_dns.domain
      servers = local.lxc_dns.servers
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

  network_interface {
    name   = local.lxc_network.name
    bridge = local.lxc_network.bridge
  }

  operating_system {
    template_file_id = local.lxc_os.template_file_id
    type             = local.lxc_os.type
  }

  lifecycle {
    ignore_changes = [
      initialization[0].user_account,
      mount_point,
    ]
  }

  depends_on = [proxmox_download_file.nixos_lxc_template]
}

# ---------------------------------------------------------------------------
# Arr — media automation (Radarr, Sonarr, Prowlarr, Bazarr)
# ---------------------------------------------------------------------------

resource "proxmox_virtual_environment_container" "arr" {
  count = var.enable_arr_stack ? 1 : 0

  vm_id         = local.guests.arr.vm_id
  node_name     = local.lxc_common.node_name
  description   = "Arr media automation — managed by NixOS flake"
  start_on_boot = local.lxc_common.start_on_boot
  started       = local.lxc_common.started
  unprivileged  = local.lxc_common.unprivileged
  tags          = ["arr", "homelab", "media", "nixos"]

  cpu { cores = var.lxc_resources.arr.cores }
  memory {
    dedicated = var.lxc_resources.arr.memory_mb
    swap      = var.lxc_resources.arr.swap_mb
  }
  disk {
    datastore_id = var.lxc_storage
    size         = var.lxc_resources.arr.disk_gb
  }
  features { nesting = true }
  device_passthrough {
    path = "/dev/net/tun"
    gid  = 0
    uid  = 0
  }

  initialization {
    hostname = "${var.homelab_name}-arr"
    dns {
      domain  = local.lxc_dns.domain
      servers = local.lxc_dns.servers
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
    name   = local.lxc_network.name
    bridge = local.lxc_network.bridge
  }

  operating_system {
    template_file_id = local.lxc_os.template_file_id
    type             = local.lxc_os.type
  }

  lifecycle {
    ignore_changes = [
      initialization[0].user_account,
      mount_point,
    ]
  }

  depends_on = [proxmox_download_file.nixos_lxc_template]
}

# ---------------------------------------------------------------------------
# qBittorrent — download client
# ---------------------------------------------------------------------------

resource "proxmox_virtual_environment_container" "qbittorrent" {
  count = var.enable_qbittorrent ? 1 : 0

  vm_id         = local.guests.qbittorrent.vm_id
  node_name     = local.lxc_common.node_name
  description   = "qBittorrent — managed by NixOS flake"
  start_on_boot = local.lxc_common.start_on_boot
  started       = local.lxc_common.started
  unprivileged  = local.lxc_common.unprivileged
  tags          = ["homelab", "media", "nixos", "qbittorrent"]

  cpu { cores = var.lxc_resources.qbittorrent.cores }
  memory {
    dedicated = var.lxc_resources.qbittorrent.memory_mb
    swap      = var.lxc_resources.qbittorrent.swap_mb
  }
  disk {
    datastore_id = var.lxc_storage
    size         = var.lxc_resources.qbittorrent.disk_gb
  }
  features { nesting = true }
  device_passthrough {
    path = "/dev/net/tun"
    gid  = 0
    uid  = 0
  }

  initialization {
    hostname = "${var.homelab_name}-qbittorrent"
    dns {
      domain  = local.lxc_dns.domain
      servers = local.lxc_dns.servers
    }
    ip_config {
      ipv4 {
        address = "${local.guests.qbittorrent.ip}/${var.network_cidr}"
        gateway = var.network_gateway
      }
    }
    user_account {
      keys = [trimspace(var.ssh_public_key)]
    }
  }

  network_interface {
    name   = local.lxc_network.name
    bridge = local.lxc_network.bridge
  }

  operating_system {
    template_file_id = local.lxc_os.template_file_id
    type             = local.lxc_os.type
  }

  lifecycle {
    ignore_changes = [
      initialization[0].user_account,
      mount_point,
    ]
  }

  depends_on = [proxmox_download_file.nixos_lxc_template]
}
