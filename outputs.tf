output "service_ips" {
  description = "Static service IP addresses."
  value = {
    adguard  = local.guests.adguard.ip
    edge     = local.guests.edge.ip
    docker   = var.enable_docker_host ? local.guests.docker.ip : null
    jellyfin = local.guests.jellyfin.ip
  }
}

output "service_hosts" {
  description = "Suggested DNS hostnames for public or internal reverse proxy use."
  value = {
    adguard    = "adguard.${var.search_domain}"
    entrypoint = var.search_domain
    jellyfin   = "jellyfin.${var.search_domain}"
  }
}

output "ansible_inventory" {
  description = "Inventory snippet for post-provisioning with Ansible."
  value       = trimspace(local.ansible_inventory)
}
