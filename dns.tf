data "cloudflare_zones" "managed" {
  count = var.enable_cloudflare_dns && var.cloudflare_zone_id == "" ? 1 : 0

  name      = var.cloudflare_zone_name
  max_items = 1
}

locals {
  cloudflare_managed_zone_id = var.cloudflare_zone_id != "" ? var.cloudflare_zone_id : data.cloudflare_zones.managed[0].result[0].id
}

# Verify ownership of lab.adre.me with Google so any Cloud Run domain mapping
# under *.lab.adre.me can be created without manual steps.
resource "google_project_service" "siteverification" {
  count   = var.enable_cloudflare_dns && var.gcp_project != "" ? 1 : 0
  project = var.gcp_project
  service = "siteverification.googleapis.com"

  disable_on_destroy = false
}

data "google_site_verification_token" "lab_domain" {
  count               = var.enable_cloudflare_dns && var.gcp_project != "" ? 1 : 0
  type                = "INET_DOMAIN"
  identifier          = "lab.${var.cloudflare_zone_name}"
  verification_method = "DNS_TXT"

  depends_on = [google_project_service.siteverification]
}

resource "cloudflare_dns_record" "lab_domain_verification" {
  count   = var.enable_cloudflare_dns && var.gcp_project != "" ? 1 : 0
  zone_id = local.cloudflare_managed_zone_id
  name    = "lab.${var.cloudflare_zone_name}"
  type    = "TXT"
  content = data.google_site_verification_token.lab_domain[0].token
  ttl     = 300
  proxied = false
  comment = "Managed by OpenTofu - Google site verification for Cloud Run domain mapping"
}

resource "google_site_verification_owner" "lab_domain" {
  count               = var.enable_cloudflare_dns && var.gcp_project != "" ? 1 : 0
  type                = "INET_DOMAIN"
  identifier          = "lab.${var.cloudflare_zone_name}"
  verification_method = "DNS_TXT"

  depends_on = [cloudflare_dns_record.lab_domain_verification]
}

resource "cloudflare_dns_record" "managed" {
  for_each = var.enable_cloudflare_dns ? {
    for record in var.cloudflare_dns_records : record.key => record
  } : {}

  zone_id = local.cloudflare_managed_zone_id
  name    = each.value.name == "" ? var.cloudflare_zone_name : "${each.value.name}.${var.cloudflare_zone_name}"
  type    = each.value.type
  content = each.value.content
  data    = each.value.data
  ttl     = each.value.ttl
  comment = each.value.comment
  proxied = each.value.proxied
}
