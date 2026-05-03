variable "proxmox_api_url" {
  description = "Proxmox API endpoint, for example https://pve.lab.adre.me:8006/."
  type        = string
  default     = "https://172.16.0.200:8006/"
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
  description = "Short name used as a prefix for guests."
  type        = string
  default     = "lab"
}

variable "network_bridge" {
  description = "Proxmox bridge used by LXCs and VMs."
  type        = string
  default     = "vmbr0"
}

variable "network_gateway" {
  description = "Default gateway for statically assigned guests."
  type        = string
  default     = "172.16.0.1"
}

variable "network_cidr" {
  description = "CIDR prefix length for the homelab network."
  type        = number
  default     = 24
}

variable "dns_servers" {
  description = "DNS servers used by guests."
  type        = list(string)
  default     = ["172.16.0.1", "1.1.1.1"]
}

variable "search_domain" {
  description = "Search domain configured in guests."
  type        = string
  default     = "lab.adre.me"
}

variable "lxc_storage" {
  description = "Proxmox storage for LXC root filesystems."
  type        = string
  default     = "local-lvm"
}

variable "vm_storage" {
  description = "Proxmox storage for VM disks."
  type        = string
  default     = "local-lvm"
}

variable "lxc_template_file_id" {
  description = "LXC template file ID, for example local:vztmpl/debian-12-standard_12.7-1_amd64.tar.zst."
  type        = string
  default     = "local:vztmpl/debian-12-standard_12.12-1_amd64.tar.zst"
}

variable "lxc_os_type" {
  description = "Container operating system type."
  type        = string
  default     = "debian"
}

variable "vm_template_id" {
  description = "VM ID of the cloud-init capable template cloned for service VMs."
  type        = number
  default     = null
}

variable "enable_docker_host" {
  description = "Create the Docker host VM. Requires vm_template_id to point at an existing cloud-init-capable VM template."
  type        = bool
  default     = false
}

variable "vm_ci_user" {
  description = "Cloud-init user created on service VMs."
  type        = string
  default     = "drew"
}

variable "jellyfin_media_bind_mount_host_path" {
  description = "Optional Proxmox host path bind-mounted into the Jellyfin container at /srv/media."
  type        = string
  default     = null
}

variable "ssh_public_key" {
  description = "SSH public key injected into service guests."
  type        = string
}

variable "service_ips" {
  description = "Static IP addresses for the provisioned guests."
  type = object({
    adguard_lxc    = string
    edge_lxc       = string
    docker_host_vm = string
    jellyfin_lxc   = string
  })
  default = {
    adguard_lxc    = "172.16.0.210"
    edge_lxc       = "172.16.0.211"
    docker_host_vm = "172.16.0.220"
    jellyfin_lxc   = "172.16.0.230"
  }
}

variable "enable_porkbun_dns" {
  description = "Manage public DNS records for porkbun_domain through the Porkbun provider."
  type        = bool
  default     = false
}

variable "porkbun_domain" {
  description = "Porkbun-managed apex domain for public DNS records."
  type        = string
  default     = "adre.me"
}

variable "porkbun_api_key" {
  description = "Porkbun API key used by the OpenTofu Porkbun provider when enable_porkbun_dns is true."
  type        = string
  default     = ""
  sensitive   = true
}

variable "porkbun_secret_api_key" {
  description = "Porkbun secret API key used by the OpenTofu Porkbun provider when enable_porkbun_dns is true."
  type        = string
  default     = ""
  sensitive   = true
}

variable "porkbun_dns_records" {
  description = "Public DNS records to manage in Porkbun once adre.me is moved there."
  type = list(object({
    key     = string
    name    = string
    type    = string
    content = string
    ttl     = optional(number, 600)
    notes   = optional(string, "Managed by OpenTofu")
  }))
  default = [
    {
      key     = "caa-letsencrypt"
      name    = ""
      type    = "CAA"
      content = "0 issue \"letsencrypt.org\""
      ttl     = 600
      notes   = "Allow Let's Encrypt certificates for adre.me"
    }
  ]
}

check "docker_host_template" {
  assert {
    condition     = !var.enable_docker_host || var.vm_template_id != null
    error_message = "enable_docker_host requires vm_template_id to be set to an existing cloud-init-capable VM template ID."
  }
}

check "porkbun_dns_credentials" {
  assert {
    condition     = !var.enable_porkbun_dns || (var.porkbun_api_key != "" && var.porkbun_secret_api_key != "")
    error_message = "enable_porkbun_dns requires porkbun_api_key and porkbun_secret_api_key, preferably through TF_VAR_porkbun_api_key and TF_VAR_porkbun_secret_api_key."
  }
}
