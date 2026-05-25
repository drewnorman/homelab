# Arr stack: Radarr, Sonarr, Prowlarr, Bazarr.
#
# Prowlarr application sync (wiring Radarr/Sonarr as sync targets and
# tagging Cloudflare-protected indexers for the Byparr proxy) is not yet
# declarative — configure via the Prowlarr UI after first deploy.
#
# Byparr (Cloudflare challenge bypass) is not in nixpkgs; package it
# separately and add as a systemd service here when ready.
{ config, lib, pkgs, ... }:

let
  mediaGroup = 1000;
in
{
  networking.firewall.allowedTCPPorts = [ 6767 7878 8191 8989 9696 ];

  users.groups.media = { gid = mediaGroup; };

  # Arr services run as their own users, all in the media group
  services.radarr  = { enable = true; group = "media"; openFirewall = false; };
  services.sonarr  = { enable = true; group = "media"; openFirewall = false; };
  services.prowlarr = { enable = true; openFirewall = false; };
  services.bazarr  = { enable = true; openFirewall = false; };

  # Shared media and downloads directories.
  # Both paths are bind-mounted from the Proxmox host by Terraform.
  systemd.tmpfiles.rules = [
    "d /mnt/media               2775 root  media -"
    "d /mnt/media/movies        2775 root  media -"
    "d /mnt/media/tv            2775 root  media -"
    "d /srv/downloads           2775 root  media -"
    "d /srv/downloads/complete  2775 root  media -"
    "d /srv/downloads/incomplete 2775 root media -"
  ];
}
