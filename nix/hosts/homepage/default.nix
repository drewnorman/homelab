{ config, lib, pkgs, allHosts, ... }:

let
  domain = "lab.adre.me";
in
{
  networking.firewall.allowedTCPPorts = [ 8082 ];

  services.homepage-dashboard = {
    enable = true;

    settings = {
      title       = "homelab";
      theme       = "dark";
      color       = "slate";
      headerStyle = "clean";
      layout = {
        Media = { style = "row"; columns = 3; };
        Services = { style = "row"; columns = 3; };
        Network = { style = "row"; columns = 2; };
      };
    };

    services = [
      {
        Media = [
          {
            Jellyfin = {
              href        = "https://jellyfin.${domain}";
              description = "Media server";
              icon        = "jellyfin.svg";
            };
          }
          {
            Radarr = {
              href        = "https://radarr.${domain}";
              description = "Movie automation";
              icon        = "radarr.svg";
            };
          }
          {
            Sonarr = {
              href        = "https://sonarr.${domain}";
              description = "TV automation";
              icon        = "sonarr.svg";
            };
          }
          {
            Prowlarr = {
              href        = "https://prowlarr.${domain}";
              description = "Indexer manager";
              icon        = "prowlarr.svg";
            };
          }
          {
            Bazarr = {
              href        = "https://bazarr.${domain}";
              description = "Subtitle manager";
              icon        = "bazarr.svg";
            };
          }
          {
            qBittorrent = {
              href        = "https://qbittorrent.${domain}";
              description = "Download client";
              icon        = "qbittorrent.svg";
            };
          }
        ];
      }
      {
        Network = [
          {
            AdGuard = {
              href        = "https://adguard.${domain}";
              description = "DNS + ad blocking";
              icon        = "adguard-home.svg";
            };
          }
          {
            Users = {
              href        = "https://users.${domain}";
              description = "LLDAP user directory";
              icon        = "ldap.svg";
            };
          }
        ];
      }
    ];

    bookmarks = [];
    widgets   = [];
  };
}
