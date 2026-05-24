output "service_ips" {
  description = "Static service IP addresses."
  value = {
    adguard         = local.guests.adguard.ip
    edge            = local.guests.edge.ip
    homepage        = local.guests.homepage.ip
    jellyfin        = local.guests.jellyfin.ip
    qbittorrent_vpn = var.enable_qbittorrent_vpn ? local.guests.qbittorrent_vpn.ip : null
    nix             = var.enable_nix_host ? local.guests.nix.ip : null
  }
}

output "service_hosts" {
  description = "Suggested DNS hostnames for public or internal reverse proxy use."
  value = {
    adguard     = "adguard.${var.search_domain}"
    bazarr      = "bazarr.${var.search_domain}"
    downloads   = "downloads.${var.search_domain}"
    entrypoint  = var.search_domain
    indexers    = "indexers.${var.search_domain}"
    jellyfin    = "jellyfin.${var.search_domain}"
    movies      = "movies.${var.search_domain}"
    qbittorrent = "qbittorrent.${var.search_domain}"
    radarr      = "radarr.${var.search_domain}"
    search      = "search.${var.search_domain}"
    sonarr      = "sonarr.${var.search_domain}"
    subtitles   = "subtitles.${var.search_domain}"
    torrents    = "torrents.${var.search_domain}"
    tv          = "tv.${var.search_domain}"
    watch       = "watch.${var.search_domain}"
    nix         = "nix.${var.search_domain}"
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

output "tailscale_edge_auth_key" {
  description = "Generated Tailscale auth key for lab-edge. Export as TAILSCALE_AUTH_KEY before running Ansible."
  value       = var.enable_tailscale_management ? tailscale_tailnet_key.edge[0].key : null
  sensitive   = true
}
