data "cloudflare_zones" "managed" {
  count = var.enable_cloudflare_dns && var.cloudflare_zone_id == "" ? 1 : 0

  name      = var.cloudflare_zone_name
  max_items = 1
}

locals {
  cloudflare_managed_zone_id = var.enable_cloudflare_dns ? (
    var.cloudflare_zone_id != "" ? var.cloudflare_zone_id : data.cloudflare_zones.managed[0].result[0].id
  ) : null
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
