output "service_ips" {
  description = "Static IP addresses for all provisioned NixOS LXC containers."
  value = {
    adguard     = local.guests.adguard.ip
    edge        = local.guests.edge.ip
    monitoring  = local.guests.monitoring.ip
    authelia    = local.guests.authelia.ip
    lldap       = local.guests.lldap.ip
    jellyfin    = local.guests.jellyfin.ip
    arr         = var.enable_arr_stack ? local.guests.arr.ip : null
    qbittorrent = var.enable_qbittorrent ? local.guests.qbittorrent.ip : null
  }
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
  value = merge(
    {
      adguard    = "root@${local.guests.adguard.ip}"
      edge       = "root@${local.guests.edge.ip}"
      monitoring = "root@${local.guests.monitoring.ip}"
      authelia   = "root@${local.guests.authelia.ip}"
      lldap      = "root@${local.guests.lldap.ip}"
      jellyfin   = "root@${local.guests.jellyfin.ip}"
    },
    var.enable_arr_stack ? { arr = "root@${local.guests.arr.ip}" } : {},
    var.enable_qbittorrent ? { qbittorrent = "root@${local.guests.qbittorrent.ip}" } : {},
  )
}

output "ansible_inventory" {
  description = "Inventory for SSH bootstrap and per-host key management."
  value = join("\n\n", compact([
    <<-EOT
    [adguard]
    lab-adguard ansible_host=${local.guests.adguard.ip} ansible_user=root
    EOT
    ,
    <<-EOT
    [edge]
    lab-edge ansible_host=${local.guests.edge.ip} ansible_user=root
    EOT
    ,
    <<-EOT
    [monitoring]
    lab-monitoring ansible_host=${local.guests.monitoring.ip} ansible_user=root
    EOT
    ,
    <<-EOT
    [authelia]
    lab-authelia ansible_host=${local.guests.authelia.ip} ansible_user=root
    EOT
    ,
    <<-EOT
    [lldap]
    lab-lldap ansible_host=${local.guests.lldap.ip} ansible_user=root
    EOT
    ,
    <<-EOT
    [media]
    lab-jellyfin ansible_host=${local.guests.jellyfin.ip} ansible_user=root
    EOT
    ,
    var.enable_arr_stack ? <<-EOT
    [arr]
    lab-arr ansible_host=${local.guests.arr.ip} ansible_user=root
    EOT
    : "",
    var.enable_qbittorrent ? <<-EOT
    [qbittorrent]
    lab-qbittorrent ansible_host=${local.guests.qbittorrent.ip} ansible_user=root
    EOT
    : "",
  ]))
}

output "tailscale_edge_auth_key" {
  description = "Generated Tailscale auth key for lab-edge. Set as the tailscale.authKeyFile sops secret."
  value       = var.enable_tailscale_management ? tailscale_tailnet_key.edge[0].key : null
  sensitive   = true
}
