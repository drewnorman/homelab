# Caddy reverse proxy with wildcard TLS via Cloudflare DNS-01 ACME.
# Uses pkgs.caddy-cloudflare from the homelab overlay (overlays/caddy-cloudflare.nix),
# which builds Caddy 2.10.0 with the caddy-dns/cloudflare plugin compiled in.
{ config, lib, pkgs, allHosts, ... }:

let
  domain = "lab.adre.me";
in
{
  networking.firewall.allowedTCPPorts = [ 80 443 ];

  # Cloudflare DNS API token for ACME DNS-01 challenge.
  # The secret file must contain a single line: CLOUDFLARE_DNS_API_TOKEN=<token>
  sops.secrets.cloudflare-dns-api-token = {
    sopsFile  = ../../secrets/edge.yaml;
    owner     = "caddy";
    # Path is used as an EnvironmentFile so Caddy picks up the token on start
    restartUnits = [ "caddy.service" ];
  };

  services.caddy = {
    enable  = true;
    package = pkgs.caddy-cloudflare;

    globalConfig = ''
      email drewnorman739@gmail.com
    '';

    # Snippet imported by routes that require SSO
    extraConfig = ''
      (authelia_guard) {
        forward_auth http://${allHosts.authelia.ip}:9091 {
          uri /api/authz/forward-auth
          copy_headers Remote-User Remote-Groups Remote-Name Remote-Email
        }
      }
    '';

    virtualHosts."*.${domain}, ${domain}" = {
      extraConfig = ''
        tls {
          dns cloudflare {env.CLOUDFLARE_DNS_API_TOKEN}
          resolvers 1.1.1.1
        }

        @authelia host auth.${domain}
        handle @authelia {
          reverse_proxy ${allHosts.authelia.ip}:9091
        }

        @lldap host users.${domain} lldap.${domain}
        handle @lldap {
          reverse_proxy ${allHosts.lldap.ip}:17170
        }

        @adguard host adguard.${domain}
        handle @adguard {
          import authelia_guard
          reverse_proxy ${allHosts.adguard.ip}:80
        }

        @homepage host ${domain}
        handle @homepage {
          import authelia_guard
          reverse_proxy ${allHosts.homepage.ip}:3000
        }

        @jellyfin host jellyfin.${domain} watch.${domain}
        handle @jellyfin {
          reverse_proxy ${allHosts.jellyfin.ip}:8096
        }

        @radarr host radarr.${domain} movies.${domain}
        handle @radarr {
          import authelia_guard
          reverse_proxy ${allHosts.arr.ip}:7878
        }

        @sonarr host sonarr.${domain} tv.${domain}
        handle @sonarr {
          import authelia_guard
          reverse_proxy ${allHosts.arr.ip}:8989
        }

        @prowlarr host prowlarr.${domain} indexers.${domain}
        handle @prowlarr {
          import authelia_guard
          reverse_proxy ${allHosts.arr.ip}:9696
        }

        @bazarr host bazarr.${domain} subtitles.${domain}
        handle @bazarr {
          import authelia_guard
          reverse_proxy ${allHosts.arr.ip}:6767
        }

        @qbittorrent host qbittorrent.${domain} downloads.${domain}
        handle @qbittorrent {
          import authelia_guard
          reverse_proxy ${allHosts.qbittorrent.ip}:8080
        }

        handle {
          respond "Unknown homelab service" 404
        }
      '';
    };
  };

  # Inject the Cloudflare token into Caddy's environment.
  # sops-nix writes the secret to a file; systemd reads it as an EnvironmentFile.
  systemd.services.caddy.serviceConfig.EnvironmentFile =
    config.sops.secrets.cloudflare-dns-api-token.path;
}
