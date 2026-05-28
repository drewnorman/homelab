variable "proxmox_api_url" {
  description = "Proxmox API endpoint, for example https://pve.lab.adre.me:8006/."
  type        = string
  default     = "https://192.168.1.200:8006/"
}

variable "proxmox_api_token_id" {
  description = "Proxmox API token ID in the form user@realm!token-name."
  type        = string
  sensitive   = true
}

variable "proxmox_api_token_secret" {
  description = "Proxmox API token secret."
  type        = string
  sensitive   = true
}

variable "proxmox_tls_insecure" {
  description = "Set true if your Proxmox API uses a self-signed certificate."
  type        = bool
  default     = true
}

variable "proxmox_node_name" {
  description = "The Proxmox node where guests will be created."
  type        = string
  default     = "norman"
}

variable "homelab_name" {
  description = "Short name used as a prefix for guest hostnames."
  type        = string
  default     = "lab"
}

variable "network_bridge" {
  description = "Proxmox bridge used by LXC containers."
  type        = string
  default     = "vmbr0"
}

variable "network_gateway" {
  description = "Default gateway for statically assigned guests."
  type        = string
  default     = "192.168.1.1"
}

variable "network_cidr" {
  description = "CIDR prefix length for the homelab network."
  type        = number
  default     = 24
}

variable "dns_servers" {
  description = "DNS servers used during initial LXC provisioning."
  type        = list(string)
  default     = ["192.168.1.1", "1.1.1.1"]
}

variable "search_domain" {
  description = "Search domain configured in guests."
  type        = string
  default     = "lab.adre.me"
}

variable "lxc_storage" {
  description = "Proxmox storage pool for LXC root filesystems."
  type        = string
  default     = "local-lvm"
}

variable "ssh_public_key" {
  description = "SSH public key injected into all NixOS LXC containers at first boot."
  type        = string
}

# ---------------------------------------------------------------------------
# Single NixOS VM target
# ---------------------------------------------------------------------------

variable "enable_core_vm" {
  description = "Create the consolidated NixOS VM. Enable during the migration, then cut it over to the AdGuard IP after validation."
  type        = bool
  default     = false
}

variable "core_vm_template_vm_id" {
  description = "VMID of an existing NixOS cloud-init/template VM to clone for lab-core."
  type        = number
  default     = null

  validation {
    condition     = !var.enable_core_vm || var.core_vm_template_vm_id != null
    error_message = "enable_core_vm requires core_vm_template_vm_id to point at a NixOS VM template."
  }
}

variable "core_vm_id" {
  description = "Stable Proxmox VMID for the consolidated NixOS VM."
  type        = number
  default     = 120
}

variable "core_vm_ip" {
  description = "Temporary static IP for lab-core before DNS cutover. Change to the old AdGuard IP after stopping the LXC."
  type        = string
  default     = "192.168.1.220"
}

variable "core_vm_storage" {
  description = "Proxmox datastore for the lab-core VM root disk."
  type        = string
  default     = "local-lvm"
}

variable "core_vm_disk_gb" {
  description = "Root disk size for lab-core in GiB. This stores fresh declarative service state, not migrated LXC state."
  type        = number
  default     = 96

  validation {
    condition     = var.core_vm_disk_gb >= 32
    error_message = "core_vm_disk_gb must be at least 32 GiB."
  }
}

variable "core_vm_cores" {
  description = "vCPU cores assigned to lab-core."
  type        = number
  default     = 4
}

variable "core_vm_memory_mb" {
  description = "Memory assigned to lab-core in MiB."
  type        = number
  default     = 8192
}

# ---------------------------------------------------------------------------
# NixOS LXC template
# ---------------------------------------------------------------------------

variable "lxc_template_file_id" {
  description = "NixOS LXC template file ID as seen by Proxmox, e.g. local:vztmpl/nixos-lxc-homelab.tar.xz."
  type        = string
  default     = "local:vztmpl/nixos-lxc-homelab.tar.xz"
}

variable "manage_lxc_template" {
  description = "Download the NixOS LXC template into Proxmox storage via OpenTofu."
  type        = bool
  default     = true
}

variable "lxc_template_datastore_id" {
  description = "Proxmox datastore to download the NixOS LXC template into."
  type        = string
  default     = "local"
}

variable "lxc_template_file_name" {
  description = "File name for the downloaded NixOS LXC template."
  type        = string
  default     = "nixos-lxc-homelab.tar.xz"
}

variable "lxc_template_url" {
  description = "Download URL for the NixOS Proxmox LXC tarball."
  type        = string
  default     = "https://hydra.nixos.org/job/nixos/release-25.11/nixos.proxmoxLXC.x86_64-linux/latest/download-by-type/file/system-tarball"
}

variable "lxc_template_download_timeout_seconds" {
  description = "Timeout for downloading the NixOS LXC template through the Proxmox API."
  type        = number
  default     = 1800
}

# ---------------------------------------------------------------------------
# Service IPs
# ---------------------------------------------------------------------------

variable "service_ips" {
  description = "Static IP addresses for each NixOS LXC container."
  type = object({
    adguard_lxc     = string
    edge_lxc        = string
    monitoring_lxc  = string
    authelia_lxc    = string
    lldap_lxc       = string
    jellyfin_lxc    = string
    arr_lxc         = string
    qbittorrent_lxc = string
  })
  default = {
    adguard_lxc     = "192.168.1.210"
    edge_lxc        = "192.168.1.211"
    monitoring_lxc  = "192.168.1.212"
    authelia_lxc    = "192.168.1.213"
    lldap_lxc       = "192.168.1.214"
    jellyfin_lxc    = "192.168.1.230"
    arr_lxc         = "192.168.1.232"
    qbittorrent_lxc = "192.168.1.233"
  }
}

variable "service_vmids" {
  description = "Stable Proxmox VMIDs for each NixOS LXC container."
  type = object({
    adguard_lxc     = number
    edge_lxc        = number
    monitoring_lxc  = number
    authelia_lxc    = number
    lldap_lxc       = number
    jellyfin_lxc    = number
    arr_lxc         = number
    qbittorrent_lxc = number
  })
  default = {
    lldap_lxc       = 100
    jellyfin_lxc    = 101
    adguard_lxc     = 102
    edge_lxc        = 103
    arr_lxc         = 104
    monitoring_lxc  = 105
    authelia_lxc    = 106
    qbittorrent_lxc = 107
  }
}

# ---------------------------------------------------------------------------
# Optional service toggles
# ---------------------------------------------------------------------------

variable "enable_arr_stack" {
  description = "Create the arr media automation LXC (Radarr, Sonarr, Prowlarr, Bazarr)."
  type        = bool
  default     = false
}

variable "enable_qbittorrent" {
  description = "Create the qBittorrent download client LXC."
  type        = bool
  default     = false
}

# ---------------------------------------------------------------------------
# Per-service sizing
# ---------------------------------------------------------------------------

variable "lxc_resources" {
  description = "CPU, memory, swap, and root disk sizing for each LXC. Memory and swap are MiB; disk is GiB."
  type = object({
    adguard = object({
      cores     = number
      memory_mb = number
      swap_mb   = number
      disk_gb   = number
    })
    edge = object({
      cores     = number
      memory_mb = number
      swap_mb   = number
      disk_gb   = number
    })
    monitoring = object({
      cores     = number
      memory_mb = number
      swap_mb   = number
      disk_gb   = number
    })
    authelia = object({
      cores     = number
      memory_mb = number
      swap_mb   = number
      disk_gb   = number
    })
    lldap = object({
      cores     = number
      memory_mb = number
      swap_mb   = number
      disk_gb   = number
    })
    jellyfin = object({
      cores     = number
      memory_mb = number
      swap_mb   = number
      disk_gb   = number
    })
    arr = object({
      cores     = number
      memory_mb = number
      swap_mb   = number
      disk_gb   = number
    })
    qbittorrent = object({
      cores     = number
      memory_mb = number
      swap_mb   = number
      disk_gb   = number
    })
  })
  default = {
    adguard = {
      cores     = 1
      memory_mb = 768
      swap_mb   = 512
      disk_gb   = 8
    }
    edge = {
      cores     = 2
      memory_mb = 1536
      swap_mb   = 1024
      disk_gb   = 8
    }
    monitoring = {
      cores     = 2
      memory_mb = 2048
      swap_mb   = 1024
      disk_gb   = 8
    }
    authelia = {
      cores     = 1
      memory_mb = 1024
      swap_mb   = 1024
      disk_gb   = 4
    }
    lldap = {
      cores     = 1
      memory_mb = 1024
      swap_mb   = 1024
      disk_gb   = 4
    }
    jellyfin = {
      cores     = 2
      memory_mb = 2048
      swap_mb   = 512
      disk_gb   = 16
    }
    arr = {
      cores     = 2
      memory_mb = 2048
      swap_mb   = 512
      disk_gb   = 8
    }
    qbittorrent = {
      cores     = 1
      memory_mb = 1024
      swap_mb   = 512
      disk_gb   = 8
    }
  }

  validation {
    condition = alltrue(flatten([
      for resource in values(var.lxc_resources) : [
        resource.cores >= 1,
        resource.memory_mb >= 256,
        resource.swap_mb >= 0,
        resource.disk_gb >= 4,
      ]
    ]))
    error_message = "Each LXC resource profile must have at least 1 core, 256 MiB memory, non-negative swap, and a 4 GiB root disk."
  }
}

variable "jellyfin_lxc_disk_size_gb" {
  description = "Deprecated. Use lxc_resources.jellyfin.disk_gb instead."
  type        = number
  default     = null
}

variable "jellyfin_media_bind_mount_host_path" {
  description = "Optional Proxmox host path bind-mounted into the Jellyfin container at /mnt/media."
  type        = string
  default     = null
}

variable "arr_downloads_bind_mount_host_path" {
  description = "Optional Proxmox host path bind-mounted into the arr container at /srv/downloads."
  type        = string
  default     = null
}

variable "qbittorrent_downloads_bind_mount_host_path" {
  description = "Optional Proxmox host path bind-mounted into the qBittorrent container at /srv/downloads. Should match arr_downloads_bind_mount_host_path so arr can import completed downloads."
  type        = string
  default     = null
}

variable "arr_media_bind_mount_host_path" {
  description = "Optional Proxmox host path bind-mounted into the arr container at /mnt/media. Should match jellyfin_media_bind_mount_host_path so hardlinks work."
  type        = string
  default     = null
}

# ---------------------------------------------------------------------------
# Tailscale
# ---------------------------------------------------------------------------

variable "enable_tailscale_management" {
  description = "Manage tailnet DNS settings and auth key generation with the Tailscale provider."
  type        = bool
  default     = false
}

variable "enable_tailscale_edge_device_management" {
  description = "Deprecated. Use enable_tailscale_core_device_management instead."
  type        = bool
  default     = false
}

variable "enable_tailscale_core_device_management" {
  description = "Manage the lab-core Tailscale device subnet routes and key expiry. Enable after lab-core has joined the tailnet."
  type        = bool
  default     = false
}

variable "tailscale_split_dns_nameserver_ip" {
  description = "Optional override for the split-DNS nameserver. Defaults to lab-core when enable_core_vm is true, otherwise legacy lab-adguard."
  type        = string
  default     = null
}

variable "tailscale_api_key" {
  description = "Tailscale API access token."
  type        = string
  sensitive   = true
  default     = ""
}

variable "tailscale_tailnet" {
  description = "Tailscale tailnet ID. Use '-' to infer the default tailnet from the credential."
  type        = string
  default     = "-"
}

variable "tailscale_auth_key_expiry_seconds" {
  description = "Expiry for generated Tailscale auth keys, in seconds."
  type        = number
  default     = 7776000
}

variable "tailscale_auth_key_reusable" {
  description = "Whether the generated Tailscale auth key can be reused."
  type        = bool
  default     = true
}

variable "tailscale_auth_key_preauthorized" {
  description = "Whether devices using the generated auth key are preauthorized."
  type        = bool
  default     = true
}

# ---------------------------------------------------------------------------
# Cloudflare DNS
# ---------------------------------------------------------------------------

variable "enable_cloudflare_dns" {
  description = "Manage public DNS records for cloudflare_zone_name through the Cloudflare provider."
  type        = bool
  default     = false
}

variable "cloudflare_zone_name" {
  description = "Cloudflare-managed apex domain."
  type        = string
  default     = "adre.me"
}

variable "cloudflare_zone_id" {
  description = "Optional Cloudflare zone ID. Leave empty to look up by name."
  type        = string
  default     = ""
}

variable "cloudflare_api_token" {
  description = "Cloudflare API token. Can also be set via CLOUDFLARE_API_TOKEN."
  type        = string
  default     = ""
  sensitive   = true
}

variable "cloudflare_dns_records" {
  description = "Public DNS records to manage in Cloudflare."
  type = list(object({
    key     = string
    name    = string
    type    = string
    content = optional(string)
    data = optional(object({
      flags = optional(number)
      tag   = optional(string)
      value = optional(string)
    }))
    ttl     = optional(number, 3600)
    comment = optional(string, "Managed by OpenTofu")
    proxied = optional(bool, false)
  }))
  default = [
    {
      key  = "caa-letsencrypt"
      name = ""
      type = "CAA"
      data = {
        flags = 0
        tag   = "issue"
        value = "letsencrypt.org"
      }
      ttl     = 3600
      comment = "Allow Let's Encrypt certificates for adre.me"
      proxied = false
    },
    {
      key  = "caa-lab-letsencrypt"
      name = "lab"
      type = "CAA"
      data = {
        flags = 0
        tag   = "issue"
        value = "letsencrypt.org"
      }
      ttl     = 3600
      comment = "Allow Let's Encrypt certificates for lab.adre.me"
      proxied = false
    },
    {
      key  = "caa-lab-letsencrypt-wildcard"
      name = "lab"
      type = "CAA"
      data = {
        flags = 0
        tag   = "issuewild"
        value = "letsencrypt.org"
      }
      ttl     = 3600
      comment = "Allow Let's Encrypt wildcard certificates for lab.adre.me"
      proxied = false
    }
  ]
}

check "cloudflare_dns_credentials" {
  assert {
    condition     = !var.enable_cloudflare_dns || var.cloudflare_zone_name != ""
    error_message = "enable_cloudflare_dns requires cloudflare_zone_name and Cloudflare API credentials."
  }
}
