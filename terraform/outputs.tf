output "service_ips" {
  description = "Static IP address for the consolidated core VM."
  value       = var.enable_core_vm ? { core = local.core_vm.ip } : {}
}

output "service_hosts" {
  description = "Expected DNS hostnames for each service behind the edge reverse proxy."
  value = {
    adguard     = "adguard.${var.search_domain}"
    authelia    = "auth.${var.search_domain}"
    bazarr      = "bazarr.${var.search_domain}"
    entrypoint  = var.search_domain
    indexers    = "indexers.${var.search_domain}"
    jellyfin    = "jellyfin.${var.search_domain}"
    lldap       = "users.${var.search_domain}"
    grafana     = "grafana.${var.search_domain}"
    monitoring  = var.search_domain
    movies      = "movies.${var.search_domain}"
    prometheus  = "prometheus.${var.search_domain}"
    alerts      = "alerts.${var.search_domain}"
    radarr      = "radarr.${var.search_domain}"
    sonarr      = "sonarr.${var.search_domain}"
    subtitles   = "subtitles.${var.search_domain}"
    tv          = "tv.${var.search_domain}"
    watch       = "watch.${var.search_domain}"
    downloads   = "downloads.${var.search_domain}"
    qbittorrent = "qbittorrent.${var.search_domain}"
  }
}

output "deploy_rs_targets" {
  description = "deploy-rs node targets. Run from the nix/ directory: deploy .#<name>"
  value       = var.enable_core_vm ? { core = "root@${local.core_vm.ip}" } : {}
}

output "tailscale_core_auth_key" {
  description = "Generated Tailscale auth key for lab-core. Set as the tailscale.authKeyFile sops secret."
  value       = var.enable_tailscale_management ? tailscale_tailnet_key.core[0].key : null
  sensitive   = true
}
