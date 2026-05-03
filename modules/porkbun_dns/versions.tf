terraform {
  required_version = ">= 1.8.0"

  required_providers {
    porkbun = {
      source  = "kyswtn/porkbun"
      version = "~> 0.1.3"
    }
  }
}
