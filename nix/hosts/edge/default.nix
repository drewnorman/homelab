{ config, lib, pkgs, allHosts, ... }:

let
  domain = "lab.adre.me";

  # Injected into each SSO-protected location block.
  autheliaGuard = ''
    auth_request /authelia;
    auth_request_set $user   $upstream_http_remote_user;
    auth_request_set $groups $upstream_http_remote_groups;
    auth_request_set $name   $upstream_http_remote_name;
    auth_request_set $email  $upstream_http_remote_email;
    proxy_set_header Remote-User   $user;
    proxy_set_header Remote-Groups $groups;
    proxy_set_header Remote-Name   $name;
    proxy_set_header Remote-Email  $email;
  '';

  # Locations added to every SSO-protected vhost.
  autheliaLocations = {
    "/authelia" = {
      proxyPass = "http://${allHosts.authelia.ip}:9091/api/authz/forward-auth";
      extraConfig = ''
        internal;
        proxy_pass_request_body off;
        proxy_set_header Content-Length "";
        proxy_set_header X-Original-URL $scheme://$http_host$request_uri;
      '';
    };
    "@authelia_login" = {
      return = "302 https://auth.${domain}/?rd=$scheme://$http_host$request_uri";
    };
  };

  # Build a vhost. sso = true adds the Authelia forward-auth guard.
  mkVhost = { backend, sso ? false, aliases ? [] }: {
    useACMEHost    = domain;
    forceSSL       = true;
    serverAliases  = aliases;
    extraConfig    = lib.optionalString sso "error_page 401 = @authelia_login;";
    locations      = lib.optionalAttrs sso autheliaLocations // {
      "/" = {
        proxyPass       = backend;
        proxyWebsockets = true;
        extraConfig     = lib.optionalString sso autheliaGuard;
      };
    };
  };

in
{
  networking.firewall.allowedTCPPorts = [ 80 443 ];

  # Edge acts as a Tailscale subnet router for 192.168.1.0/24, making all
  # homelab hosts reachable from the tailnet (including the GHA deploy runner).
  # After first deploy: approve the advertised route in the Tailscale admin console.
  services.tailscale = {
    authKeyFile        = config.sops.secrets.tailscale-auth-key.path;
    useRoutingFeatures = "server";
    extraUpFlags       = [ "--advertise-routes=192.168.1.0/24" ];
  };

  sops.secrets.cloudflare-dns-api-token = {
    sopsFile     = ../../secrets/edge.yaml;
    owner        = "acme";
    group        = "acme";
    restartUnits = [ "acme-${domain}.service" ];
  };
  sops.secrets.tailscale-auth-key = {
    sopsFile = ../../secrets/edge.yaml;
    owner    = "root";
  };

  security.acme = {
    acceptTerms = true;
    defaults.email = "drewnorman739@gmail.com";
    certs.${domain} = {
      domain          = "*.${domain}";
      extraDomainNames = [ domain ];
      dnsProvider     = "cloudflare";
      environmentFile = config.sops.secrets.cloudflare-dns-api-token.path;
      group           = "nginx";
    };
  };

  services.nginx = {
    enable = true;
    recommendedProxySettings = true;
    recommendedTlsSettings   = true;
    recommendedOptimisation  = true;
    recommendedGzipSettings  = true;

    virtualHosts = {
      "auth.${domain}"        = mkVhost { backend = "http://${allHosts.authelia.ip}:9091"; };
      "users.${domain}"       = mkVhost { backend = "http://${allHosts.lldap.ip}:17170";   aliases = [ "lldap.${domain}" ]; };
      "adguard.${domain}"     = mkVhost { backend = "http://${allHosts.adguard.ip}:80";    sso = true; };
      "${domain}"             = mkVhost { backend = "http://${allHosts.monitoring.ip}:3000"; sso = true; };
      "grafana.${domain}"     = mkVhost { backend = "http://${allHosts.monitoring.ip}:3000"; sso = true; };
      "prometheus.${domain}"  = mkVhost { backend = "http://${allHosts.monitoring.ip}:9090"; sso = true; };
      "alerts.${domain}"      = mkVhost { backend = "http://${allHosts.monitoring.ip}:9093"; sso = true; aliases = [ "alertmanager.${domain}" ]; };
      "jellyfin.${domain}"    = mkVhost { backend = "http://${allHosts.jellyfin.ip}:8096"; aliases = [ "watch.${domain}" ]; };
      "radarr.${domain}"      = mkVhost { backend = "http://${allHosts.arr.ip}:7878";      sso = true; aliases = [ "movies.${domain}" ]; };
      "sonarr.${domain}"      = mkVhost { backend = "http://${allHosts.arr.ip}:8989";      sso = true; aliases = [ "tv.${domain}" ]; };
      "prowlarr.${domain}"    = mkVhost { backend = "http://${allHosts.arr.ip}:9696";      sso = true; aliases = [ "indexers.${domain}" ]; };
      "bazarr.${domain}"      = mkVhost { backend = "http://${allHosts.arr.ip}:6767";      sso = true; aliases = [ "subtitles.${domain}" ]; };
      "qbittorrent.${domain}" = mkVhost { backend = "http://${allHosts.qbittorrent.ip}:8080"; sso = true; aliases = [ "downloads.${domain}" ]; };
    };
  };

  # ACME certificates must survive container restarts.
  environment.persistence."/persist" = {
    directories = [ "/var/lib/acme" ];
  };
}
