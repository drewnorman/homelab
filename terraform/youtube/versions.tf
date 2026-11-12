terraform {
  required_version = ">= 1.8.0"

  backend "gcs" {
    bucket = "drew-infra-tofu-state"
    prefix = "homelab/youtube/prod"
  }

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "= 7.46.0"
    }
  }
}
