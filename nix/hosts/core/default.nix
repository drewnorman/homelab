{ config, lib, pkgs, hostMeta, ... }:

let
  domain = "lab.adre.me";
  baseDn = "dc=lab,dc=adre,dc=me";
  enableTls = true;
  externalScheme = if enableTls then "https" else "http";

  local = {
    adguard     = "127.0.0.1:3001";
    authelia    = "127.0.0.1:9091";
    lldapHttp   = "127.0.0.1:17170";
    lldapLdap   = "127.0.0.1:3890";
    grafana     = "127.0.0.1:3000";
    prometheus  = "127.0.0.1:9090";
    alertmanager = "127.0.0.1:9093";
    jellyfin    = "127.0.0.1:8096";
    radarr      = "127.0.0.1:7878";
    sonarr      = "127.0.0.1:8989";
    prowlarr    = "127.0.0.1:9696";
    bazarr      = "127.0.0.1:6767";
    qbittorrent = "127.0.0.1:8080";
  };

  mediaGroup = 1000;

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

  autheliaLocations = {
    "/authelia" = {
      proxyPass = "http://${local.authelia}/api/authz/auth-request";
      extraConfig = ''
        internal;
        proxy_pass_request_body off;
        proxy_set_header Content-Length "";
        proxy_set_header X-Original-Method $request_method;
        proxy_set_header X-Original-URL $scheme://$http_host$request_uri;
        proxy_set_header X-Forwarded-Method $request_method;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header X-Forwarded-Host $http_host;
        proxy_set_header X-Forwarded-URI $request_uri;
        proxy_set_header X-Forwarded-For $remote_addr;
      '';
    };
    "@authelia_login" = {
      return = "302 https://auth.${domain}/?rd=$scheme://$http_host$request_uri";
    };
  };

  mkVhost = { backend, sso ? false, aliases ? [] }: {
    serverAliases = aliases;
    extraConfig   = lib.optionalString (sso && enableTls) "error_page 401 = @authelia_login;";
    locations     = lib.optionalAttrs (sso && enableTls) autheliaLocations // {
      "/" = {
        proxyPass       = "http://${backend}";
        proxyWebsockets = true;
        extraConfig     = lib.optionalString (sso && enableTls) autheliaGuard;
      };
    };
  } // lib.optionalAttrs enableTls {
    useACMEHost = domain;
    forceSSL = true;
  };

  dashboardDir = pkgs.writeTextDir "homelab-node-overview.json" (builtins.toJSON {
    uid = "homelab-node-overview";
    title = "Homelab Node Overview";
    tags = [ "homelab" "nodes" ];
    timezone = "browser";
    refresh = "30s";
    schemaVersion = 39;
    version = 1;
    time = {
      from = "now-6h";
      to = "now";
    };
    panels = [
      {
        id = 1;
        type = "stat";
        title = "Core Up";
        datasource = { type = "prometheus"; uid = "prometheus"; };
        gridPos = { h = 4; w = 6; x = 0; y = 0; };
        targets = [{ expr = "up{job=\"node\",host=\"core\"}"; refId = "A"; }];
      }
      {
        id = 2;
        type = "timeseries";
        title = "CPU Busy";
        datasource = { type = "prometheus"; uid = "prometheus"; };
        gridPos = { h = 8; w = 12; x = 0; y = 4; };
        targets = [{
          expr = "100 * (1 - avg(rate(node_cpu_seconds_total{job=\"node\",mode=\"idle\",host=\"core\"}[5m])))";
          refId = "A";
        }];
        fieldConfig.defaults.unit = "percent";
      }
      {
        id = 3;
        type = "timeseries";
        title = "Memory Used";
        datasource = { type = "prometheus"; uid = "prometheus"; };
        gridPos = { h = 8; w = 12; x = 12; y = 4; };
        targets = [{
          expr = "100 * (1 - (node_memory_MemAvailable_bytes{job=\"node\",host=\"core\"} / node_memory_MemTotal_bytes{job=\"node\",host=\"core\"}))";
          refId = "A";
        }];
        fieldConfig.defaults.unit = "percent";
      }
      {
        id = 4;
        type = "timeseries";
        title = "Root Filesystem Used";
        datasource = { type = "prometheus"; uid = "prometheus"; };
        gridPos = { h = 8; w = 12; x = 0; y = 12; };
        targets = [{
          expr = "100 * (1 - (node_filesystem_avail_bytes{job=\"node\",mountpoint=\"/\",fstype!=\"rootfs\",host=\"core\"} / node_filesystem_size_bytes{job=\"node\",mountpoint=\"/\",fstype!=\"rootfs\",host=\"core\"}))";
          refId = "A";
        }];
        fieldConfig.defaults.unit = "percent";
      }
    ];
  });
in
{
  networking.firewall.allowedTCPPorts = [ 53 80 443 9100 ];
  networking.firewall.allowedUDPPorts = [ 53 ];

  users.groups.media = { gid = mediaGroup; };
  users.groups.lldap-secrets = {};

  systemd.tmpfiles.rules = [
    "d /srv/homelab 0755 root root -"
    "d /srv/media 2775 root media -"
    "d /srv/media/movies 2775 root media -"
    "d /srv/media/tv 2775 root media -"
    "d /srv/downloads 2775 root media -"
    "d /srv/downloads/complete 2775 root media -"
    "d /srv/downloads/incomplete 2775 root media -"
    "d /var/log/authelia 0750 authelia-main authelia-main -"
  ];

  sops.secrets.cloudflare-dns-api-token = lib.mkIf enableTls {
    sopsFile = ../../secrets/edge.yaml;
    owner = "acme";
    group = "acme";
    restartUnits = [ "acme-${domain}.service" ];
  };
  sops.secrets.tailscale-auth-key = {
    sopsFile = ../../secrets/edge.yaml;
    owner = "root";
  };
  sops.secrets.lldap-jwt-secret = {
    sopsFile = ../../secrets/lldap.yaml;
    owner = "root";
    group = "lldap-secrets";
    mode = "0440";
  };
  sops.secrets.lldap-admin-password = {
    sopsFile = ../../secrets/lldap.yaml;
    owner = "root";
    group = "lldap-secrets";
    mode = "0440";
  };
  sops.secrets."lldap-user-drew-password" = {
    sopsFile = ../../secrets/lldap.yaml;
    owner = "root";
    group = "lldap-secrets";
    mode = "0440";
  };
  sops.secrets.authelia-jwt-secret = {
    sopsFile = ../../secrets/authelia.yaml;
    owner = "authelia-main";
  };
  sops.secrets.authelia-session-secret = {
    sopsFile = ../../secrets/authelia.yaml;
    owner = "authelia-main";
  };
  sops.secrets.authelia-storage-encryption-key = {
    sopsFile = ../../secrets/authelia.yaml;
    owner = "authelia-main";
  };
  sops.secrets.authelia-lldap-password = {
    sopsFile = ../../secrets/authelia.yaml;
    owner = "authelia-main";
  };

  services.tailscale = {
    enable = true;
    authKeyFile = config.sops.secrets.tailscale-auth-key.path;
    useRoutingFeatures = "server";
    extraUpFlags = [
      "--accept-dns=false"
      "--advertise-routes=192.168.1.0/24"
    ];
  };

  security.acme = lib.mkIf enableTls {
    acceptTerms = true;
    defaults.email = "drewnorman739@gmail.com";
    certs.${domain} = {
      domain = "*.${domain}";
      extraDomainNames = [ domain ];
      dnsProvider = "cloudflare";
      environmentFile = config.sops.secrets.cloudflare-dns-api-token.path;
      group = "nginx";
    };
  };
  systemd.services."acme-${domain}".serviceConfig.TimeoutStartSec = lib.mkIf enableTls "10min";

  services.nginx = {
    enable = true;
    recommendedProxySettings = true;
    recommendedTlsSettings = true;
    recommendedOptimisation = true;
    recommendedGzipSettings = true;

    virtualHosts = {
      "auth.${domain}" = mkVhost { backend = local.authelia; };
      "users.${domain}" = mkVhost { backend = local.lldapHttp; aliases = [ "lldap.${domain}" ]; };
      "adguard.${domain}" = mkVhost { backend = local.adguard; sso = true; };
      "${domain}" = mkVhost { backend = local.grafana; sso = true; };
      "grafana.${domain}" = mkVhost { backend = local.grafana; sso = true; };
      "prometheus.${domain}" = mkVhost { backend = local.prometheus; sso = true; };
      "alerts.${domain}" = mkVhost { backend = local.alertmanager; sso = true; aliases = [ "alertmanager.${domain}" ]; };
      "jellyfin.${domain}" = mkVhost { backend = local.jellyfin; aliases = [ "watch.${domain}" ]; };
      "radarr.${domain}" = mkVhost { backend = local.radarr; sso = true; aliases = [ "movies.${domain}" ]; };
      "sonarr.${domain}" = mkVhost { backend = local.sonarr; sso = true; aliases = [ "tv.${domain}" ]; };
      "prowlarr.${domain}" = mkVhost { backend = local.prowlarr; sso = true; aliases = [ "indexers.${domain}" ]; };
      "bazarr.${domain}" = mkVhost { backend = local.bazarr; sso = true; aliases = [ "subtitles.${domain}" ]; };
      "qbittorrent.${domain}" = mkVhost { backend = local.qbittorrent; sso = true; aliases = [ "downloads.${domain}" ]; };
    };
  };

  services.adguardhome = {
    enable = true;
    openFirewall = false;
    host = "127.0.0.1";
    port = 3001;
    mutableSettings = false;
    settings = {
      users = [
        {
          name = "admin";
          password = "$2b$10$5KC8Aa8cZDMYRQyRUa2As./HhqCHUXSE4UHwiBENpavLDfr8fCYkO";
        }
      ];
      dns = {
        bind_hosts = [ "0.0.0.0" ];
        port = 53;
        upstream_dns = [ "https://dns.cloudflare.com/dns-query" ];
        bootstrap_dns = [
          "9.9.9.10"
          "149.112.112.10"
          "2620:fe::10"
          "2620:fe::fe:10"
        ];
        fallback_dns = [ "https://dns.google/dns-query" ];
        blocked_hosts = [ "version.bind" "id.server" "hostname.bind" ];
      };
      filtering.rewrites = [
        { domain = domain; answer = hostMeta.ip; }
        { domain = "*.${domain}"; answer = hostMeta.ip; }
      ];
      filters = [
        { enabled = true; id = 1; url = "https://adguardteam.github.io/HostlistsRegistry/assets/filter_1.txt"; name = "AdGuard DNS filter"; }
        { enabled = false; id = 2; url = "https://adguardteam.github.io/HostlistsRegistry/assets/filter_2.txt"; name = "AdAway Default Blocklist"; }
        { enabled = true; id = 1776125343; url = "https://small.oisd.nl/"; name = "OISD Small"; }
        { enabled = true; id = 1776125344; url = "https://cdn.jsdelivr.net/gh/hagezi/dns-blocklists@latest/adblock/pro.plus.txt"; name = "HaGeZi Pro++"; }
        { enabled = true; id = 1776125345; url = "https://cdn.jsdelivr.net/gh/hagezi/dns-blocklists@latest/adblock/tif.txt"; name = "HaGeZi TIF"; }
      ];
      user_rules = [
        "||darnobedienceupscale.com^"
        "||nublet.shop^"
        "||janitorprecisiontrio.com^"
        "||rhussvelter.com^"
        "||matarketogen.qpon^"
      ];
      trusted_proxies = [ "127.0.0.0/8" "::1/128" ];
    };
  };

  systemd.services.lldap.serviceConfig.SupplementaryGroups = [ "lldap-secrets" ];
  services.lldap = {
    enable = true;
    settings = {
      http_port = 17170;
      ldap_port = 3890;
      ldap_base_dn = baseDn;
      http_url = "https://users.${domain}";
      data_dir = "/var/lib/lldap";
    };
    environment = {
      LLDAP_JWT_SECRET_FILE = config.sops.secrets.lldap-jwt-secret.path;
      LLDAP_LDAP_USER_PASS_FILE = config.sops.secrets.lldap-admin-password.path;
    };
    provision = {
      enable = true;
      adminPasswordFile = config.sops.secrets.lldap-admin-password.path;
      groups = [
        { name = "lldap_strict_readonly"; displayName = "LLDAP Read-Only"; }
        { name = "media"; displayName = "Media Users"; }
      ];
      users = [
        {
          username = "drew";
          email = "drewnorman739@gmail.com";
          displayName = "Drew Norman";
          groups = [ "lldap_strict_readonly" "media" ];
          passwordFile = config.sops.secrets."lldap-user-drew-password".path;
        }
      ];
    };
  };

  services.authelia.instances.main = {
    enable = true;
    secrets = {
      jwtSecretFile = config.sops.secrets.authelia-jwt-secret.path;
      sessionSecretFile = config.sops.secrets.authelia-session-secret.path;
      storageEncryptionKeyFile = config.sops.secrets.authelia-storage-encryption-key.path;
    };
    settings = {
      theme = "dark";
      server.address = "tcp://127.0.0.1:9091";
      log = {
        level = "info";
        keep_stdout = true;
      };
      totp = {
        issuer = domain;
        period = 30;
        skew = 1;
      };
      authentication_backend.ldap = {
        implementation = "lldap";
        address = "ldap://${local.lldapLdap}";
        base_dn = baseDn;
        user = "uid=admin,ou=people,${baseDn}";
      };
      access_control.default_policy = "one_factor";
      session.cookies = [
        {
          name = "authelia_session";
          domain = domain;
          authelia_url = "https://auth.${domain}";
          default_redirection_url = "https://${domain}";
          expiration = "12h";
          inactivity = "1h";
          remember_me = "1M";
        }
      ];
      regulation = {
        max_retries = 5;
        find_time = "5m";
        ban_time = "15m";
      };
      storage.local.path = "/var/lib/authelia-main/db.sqlite3";
      notifier.filesystem.filename = "/var/lib/authelia-main/notification.txt";
    };
  };

  systemd.services."authelia-main".environment = {
    AUTHELIA_AUTHENTICATION_BACKEND_LDAP_PASSWORD_FILE =
      config.sops.secrets.authelia-lldap-password.path;
  };

  services.grafana = {
    enable = true;
    settings = {
      server = {
        http_addr = "127.0.0.1";
        http_port = 3000;
        domain = "grafana.${domain}";
        root_url = "${externalScheme}://grafana.${domain}";
      };
      users.allow_sign_up = false;
      analytics.reporting_enabled = false;
    };
    provision = {
      enable = true;
      datasources.settings.datasources = [
        {
          name = "Prometheus";
          uid = "prometheus";
          type = "prometheus";
          access = "proxy";
          url = "http://${local.prometheus}";
          isDefault = true;
        }
      ];
      dashboards.settings.providers = [
        {
          name = "Homelab";
          type = "file";
          disableDeletion = false;
          editable = true;
          options.path = dashboardDir;
        }
      ];
    };
  };

  services.prometheus = {
    enable = true;
    listenAddress = "127.0.0.1";
    port = 9090;
    globalConfig.scrape_interval = "30s";
    scrapeConfigs = [
      {
        job_name = "prometheus";
        static_configs = [{ targets = [ local.prometheus ]; }];
      }
      {
        job_name = "node";
        static_configs = [{
          targets = [ "127.0.0.1:9100" ];
          labels.host = "core";
        }];
      }
    ];
    alertmanagers = [
      {
        scheme = "http";
        static_configs = [{ targets = [ local.alertmanager ]; }];
      }
    ];
    rules = [
      ''
        groups:
          - name: homelab
            rules:
              - alert: NodeExporterDown
                expr: up{job="node"} == 0
                for: 5m
                labels:
                  severity: warning
                annotations:
                  summary: "Node exporter is down on {{ $labels.host }}"
              - alert: RootFilesystemNearlyFull
                expr: 100 * (1 - (node_filesystem_avail_bytes{job="node",mountpoint="/",fstype!="rootfs"} / node_filesystem_size_bytes{job="node",mountpoint="/",fstype!="rootfs"})) > 85
                for: 15m
                labels:
                  severity: warning
                annotations:
                  summary: "Root filesystem is over 85% used on {{ $labels.host }}"
              - alert: HighMemoryUsage
                expr: 100 * (1 - (node_memory_MemAvailable_bytes{job="node"} / node_memory_MemTotal_bytes{job="node"})) > 90
                for: 15m
                labels:
                  severity: warning
                annotations:
                  summary: "Memory usage is over 90% on {{ $labels.host }}"
      ''
    ];
    alertmanager = {
      enable = true;
      listenAddress = "127.0.0.1";
      port = 9093;
      configuration = {
        route = {
          receiver = "null";
          group_by = [ "alertname" "host" ];
        };
        receivers = [{ name = "null"; }];
      };
    };
  };

  services.jellyfin = {
    enable = true;
    openFirewall = false;
    group = "media";
  };

  services.radarr = { enable = true; group = "media"; openFirewall = false; };
  services.sonarr = { enable = true; group = "media"; openFirewall = false; };
  services.prowlarr = { enable = true; openFirewall = false; };
  services.bazarr = { enable = true; openFirewall = false; };

  users.users.qbittorrent = {
    isSystemUser = true;
    group = "qbittorrent";
    extraGroups = [ "media" ];
    home = "/var/lib/qbittorrent";
  };
  users.groups.qbittorrent = {};

  systemd.services.qbittorrent = {
    description = "qBittorrent-nox download client";
    after = [ "network.target" ];
    wantedBy = [ "multi-user.target" ];
    preStart = ''
      cfg=/var/lib/qbittorrent/qBittorrent/qBittorrent.conf
      if [ ! -f "$cfg" ]; then
        mkdir -p "$(dirname "$cfg")"
        cat > "$cfg" <<'EOF'
[BitTorrent]
Session\DefaultSavePath=/srv/downloads/
Session\TempPath=/srv/downloads/incomplete/
[Preferences]
WebUI\LocalHostAuth=false
EOF
      fi
    '';
    serviceConfig = {
      User = "qbittorrent";
      Group = "qbittorrent";
      ExecStart = "${pkgs.qbittorrent-nox}/bin/qbittorrent-nox --webui-port=8080 --profile=/var/lib/qbittorrent";
      Restart = "on-failure";
      StateDirectory = "qbittorrent";
    };
  };
}
