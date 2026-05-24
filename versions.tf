terraform {
  required_version = ">= 1.8.0"

  backend "gcs" {
    bucket = "drew-infra-tofu-state"
    prefix = "homelab/prod"
  }

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.100"
    }
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 5.0"
    }
    tailscale = {
      source  = "tailscale/tailscale"
      version = "~> 0.28"
    }
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
  }
}
