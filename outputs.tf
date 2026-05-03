output "service_ips" {
  description = "Static service IP addresses."
  value = {
    adguard  = local.guests.adguard.ip
    edge     = local.guests.edge.ip
    docker   = var.enable_docker_host ? local.guests.docker.ip : null
    jellyfin = local.guests.jellyfin.ip
    nix      = var.enable_nix_host ? local.guests.nix.ip : null
  }
}

output "service_hosts" {
  description = "Suggested DNS hostnames for public or internal reverse proxy use."
  value = {
    adguard    = "adguard.${var.search_domain}"
    entrypoint = var.search_domain
    jellyfin   = "jellyfin.${var.search_domain}"
    nix        = "nix.${var.search_domain}"
  }
}

output "nix_host" {
  description = "Nix host deployment details."
  value = {
    enabled    = var.enable_nix_host
    hostname   = "${var.homelab_name}-nix"
    fqdn       = "nix.${var.search_domain}"
    ip         = local.guests.nix.ip
    flake      = "${var.nix_config_repo_url}#${var.nix_config_flake_host}"
    ssh_target = "${var.vm_ci_user}@nix.${var.search_domain}"
  }
}

output "ansible_inventory" {
  description = "Inventory snippet for post-provisioning with Ansible."
  value       = trimspace(local.ansible_inventory)
}
