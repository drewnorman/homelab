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

variable "proxmox_ssh_host" {
  description = "SSH hostname or address for the Proxmox node, used for root-only host disk passthrough commands."
  type        = string
  default     = "192.168.1.200"
}

variable "homelab_name" {
  description = "Short name used as a prefix for guest hostnames."
  type        = string
  default     = "lab"
}

variable "network_bridge" {
  description = "Proxmox bridge used by lab-core."
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
  description = "DNS servers used during initial VM provisioning."
  type        = list(string)
  default     = ["192.168.1.1", "1.1.1.1"]
}

variable "search_domain" {
  description = "Search domain configured in guests."
  type        = string
  default     = "lab.adre.me"
}

variable "ssh_public_key" {
  description = "SSH public key injected into lab-core at first boot."
  type        = string
}

# ---------------------------------------------------------------------------
# Single NixOS VM target
# ---------------------------------------------------------------------------

variable "enable_core_vm" {
  description = "Create the consolidated NixOS VM."
  type        = bool
  default     = true
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
  description = "Static IP for lab-core. This is the router DNS IP."
  type        = string
  default     = "192.168.1.210"
}

variable "core_vm_storage" {
  description = "Proxmox datastore for the lab-core VM root disk."
  type        = string
  default     = "local-lvm"
}

variable "core_vm_disk_gb" {
  description = "Root disk size for lab-core in GiB. This stores fresh declarative service state."
  type        = number
  default     = 96

  validation {
    condition     = var.core_vm_disk_gb >= 32
    error_message = "core_vm_disk_gb must be at least 32 GiB."
  }
}

variable "core_vm_media_disk_path" {
  description = "Stable Proxmox host path for the external media SSD partition passed through to lab-core."
  type        = string
  default     = "/dev/disk/by-uuid/06d2efe6-c0b5-411c-8747-3a4ff0242979"
}

variable "core_vm_cores" {
  description = "vCPU cores assigned to lab-core."
  type        = number
  default     = 6
}

variable "core_vm_memory_mb" {
  description = "Memory assigned to lab-core in MiB."
  type        = number
  default     = 12288
}

# ---------------------------------------------------------------------------
# Tailscale
# ---------------------------------------------------------------------------

variable "enable_tailscale_management" {
  description = "Manage tailnet DNS settings and auth key generation with the Tailscale provider."
  type        = bool
  default     = false
}

variable "enable_tailscale_core_device_management" {
  description = "Manage the lab-core Tailscale device subnet routes and key expiry. Enable after lab-core has joined the tailnet."
  type        = bool
  default     = false
}

variable "tailscale_split_dns_nameserver_ip" {
  description = "Optional override for the split-DNS nameserver. Defaults to lab-core."
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
