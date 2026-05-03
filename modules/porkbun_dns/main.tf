resource "porkbun_dns_record" "managed" {
  for_each = {
    for record in var.records : record.key => record
  }

  domain  = var.domain
  name    = each.value.name
  type    = each.value.type
  content = each.value.content
  ttl     = each.value.ttl
  notes   = each.value.notes
}
