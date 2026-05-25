{ config, lib, pkgs, ... }:
{
  networking.firewall.allowedTCPPorts = [ 8096 ];

  services.jellyfin = {
    enable    = true;
    openFirewall = true;
    # Jellyfin runs as the jellyfin user; grant it access to the media group
    # so it can read bind-mounted media from the Proxmox host.
    group     = "media";
  };

  users.groups.media = {
    gid = 1000;
  };

  # Media is bind-mounted into /mnt/media by Terraform/Proxmox.
  # Ensure the directory exists with correct group ownership.
  systemd.tmpfiles.rules = [
    "d /mnt/media        2775 root media -"
    "d /mnt/media/movies 2775 root media -"
    "d /mnt/media/tv     2775 root media -"
  ];
}
