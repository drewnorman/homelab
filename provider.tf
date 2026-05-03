provider "proxmox" {
  endpoint  = var.proxmox_api_url
  api_token = "${var.proxmox_api_token_id}=${var.proxmox_api_token_secret}"
  insecure  = var.proxmox_tls_insecure

  ssh {
    username = "root"
    agent    = true
  }
}

provider "porkbun" {
  api_key        = var.enable_porkbun_dns ? var.porkbun_api_key : "disabled"
  secret_api_key = var.enable_porkbun_dns ? var.porkbun_secret_api_key : "disabled"
}
