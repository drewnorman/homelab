provider "proxmox" {
  endpoint  = var.proxmox_api_url
  api_token = "${var.proxmox_api_token_id}=${var.proxmox_api_token_secret}"
  insecure  = var.proxmox_tls_insecure

  ssh {
    username = "root"
    agent    = true
  }
}

provider "cloudflare" {
  api_token = var.cloudflare_api_token != "" ? var.cloudflare_api_token : null
}

provider "tailscale" {
  api_key = var.tailscale_api_key != "" ? var.tailscale_api_key : null
  tailnet = var.tailscale_tailnet
}

provider "google" {
  project = var.gcp_project != "" ? var.gcp_project : null
  region  = var.gcp_region
}

provider "random" {}

