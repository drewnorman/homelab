terraform {
  required_version = ">= 1.8.0"

  backend "gcs" {
    bucket = "drew-infra-tofu-state"
    prefix = "homelab/openai/prod"
  }

  required_providers {
    openai = {
      source  = "registry.terraform.io/openai/openai"
      version = "~> 1.0.0"
    }
  }
}
