output "service_ips" {
  description = "Static IP addresses for all provisioned NixOS LXC containers."
  value = {
    adguard         = local.guests.adguard.ip
    edge            = local.guests.edge.ip
    homepage        = local.guests.homepage.ip
    authelia        = local.guests.authelia.ip
    lldap           = local.guests.lldap.ip
    jellyfin        = local.guests.jellyfin.ip
    arr             = var.enable_arr_stack ? local.guests.arr.ip : null
    qbittorrent_vpn = var.enable_qbittorrent_vpn ? local.guests.qbittorrent_vpn.ip : null
  }
}

output "service_hosts" {
  description = "Expected DNS hostnames for each service behind the edge reverse proxy."
  value = {
    adguard     = "adguard.${var.search_domain}"
    authelia    = "auth.${var.search_domain}"
    bazarr      = "bazarr.${var.search_domain}"
    downloads   = "downloads.${var.search_domain}"
    entrypoint  = var.search_domain
    indexers    = "indexers.${var.search_domain}"
    jellyfin    = "jellyfin.${var.search_domain}"
    lldap       = "users.${var.search_domain}"
    movies      = "movies.${var.search_domain}"
    radarr      = "radarr.${var.search_domain}"
    sonarr      = "sonarr.${var.search_domain}"
    subtitles   = "subtitles.${var.search_domain}"
    tv          = "tv.${var.search_domain}"
    watch       = "watch.${var.search_domain}"
  }
}

output "deploy_rs_targets" {
  description = "deploy-rs node targets. Run from the nix/ directory: deploy .#<name>"
  value = merge(
    {
      adguard  = "root@${local.guests.adguard.ip}"
      edge     = "root@${local.guests.edge.ip}"
      homepage = "root@${local.guests.homepage.ip}"
      authelia = "root@${local.guests.authelia.ip}"
      lldap    = "root@${local.guests.lldap.ip}"
      jellyfin = "root@${local.guests.jellyfin.ip}"
    },
    var.enable_arr_stack ? { arr = "root@${local.guests.arr.ip}" } : {},
    var.enable_qbittorrent_vpn ? { qbittorrent = "root@${local.guests.qbittorrent_vpn.ip}" } : {},
  )
}

output "tailscale_edge_auth_key" {
  description = "Generated Tailscale auth key for lab-edge. Set as the tailscale.authKeyFile sops secret."
  value       = var.enable_tailscale_management ? tailscale_tailnet_key.edge[0].key : null
  sensitive   = true
}
