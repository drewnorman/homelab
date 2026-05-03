module "porkbun_dns" {
  count = var.enable_porkbun_dns ? 1 : 0

  source = "./modules/porkbun_dns"

  domain  = var.porkbun_domain
  records = var.porkbun_dns_records
}
