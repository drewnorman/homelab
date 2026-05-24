# Caddy reverse proxy with wildcard TLS via Cloudflare DNS-01 ACME.
#
# Caddy needs the cloudflare DNS provider plugin to do DNS-01 challenges.
# Build a custom Caddy package with the plugin by overriding in an overlay,
# or use the xcaddy approach. Example overlay (add to flake.nix nixpkgs.overlays):
#
#   caddy-cloudflare = pkgs.caddy.override (old: {
#     buildGoModule = args: old.buildGoModule (args // {
#       subPackages = [ "cmd/caddy" ];
#       # patch main.go to import caddy-dns/cloudflare
#     });
#   });
#
# For now the package defaults to standard Caddy; swap in the custom build once
# the overlay is wired up.
{ config, lib, pkgs, allHosts, ... }:

let
  domain = "lab.adre.me";
in
{
  networking.firewall.allowedTCPPorts = [ 80 443 ];

  # Cloudflare DNS API token for ACME DNS-01 challenge
  sops.secrets.cloudflare-dns-api-token = {
    sopsFile = ../../secrets/edge.yaml;
    owner    = "caddy";
  };

  services.caddy = {
    enable = true;

    # Global ACME config — Caddy handles cert renewal automatically.
    # The Cloudflare plugin must be compiled in (see note above).
    globalConfig = ''
      email drewnorman739@gmail.com
    '';

    # Snippet: forward-auth via Authelia
    extraConfig = ''
      (authelia_guard) {
        forward_auth http://${allHosts.authelia.ip}:9091 {
          uri /api/authz/forward-auth
          copy_headers Remote-User Remote-Groups Remote-Name Remote-Email
        }
      }
    '';

    # Main virtual host block covering *.lab.adre.me and lab.adre.me
    virtualHosts."*.${domain}, ${domain}" = {
      extraConfig = ''
        # TLS via Cloudflare DNS-01 — requires caddy-dns/cloudflare plugin
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

        @qbittorrent host qbittorrent.${domain} downloads.${domain} torrents.${domain}
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

  # Expose the Cloudflare token as an environment variable for Caddy
  systemd.services.caddy.serviceConfig.EnvironmentFile =
    config.sops.secrets.cloudflare-dns-api-token.path;
}
