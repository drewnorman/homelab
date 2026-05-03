variable "domain" {
  description = "Porkbun-managed apex domain for DNS records."
  type        = string
}

variable "records" {
  description = "DNS records to manage in Porkbun."
  type = list(object({
    key     = string
    name    = string
    type    = string
    content = string
    ttl     = optional(number, 600)
    notes   = optional(string, "Managed by OpenTofu")
  }))
}
