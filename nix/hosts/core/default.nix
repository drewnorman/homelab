{ config, lib, pkgs, pkgsJellyfin, hostMeta, ... }:

let
  domain = "lab.adre.me";
  baseDn = "dc=lab,dc=adre,dc=me";
  enableTls = true;
  customAutheliaLogin = true;
  externalScheme = if enableTls then "https" else "http";
  jellyfinLdapPluginVersion = "22.0.0.0";
  jellyfinLdapPluginZip = pkgs.fetchurl {
    url = "https://repo.jellyfin.org/files/plugin/ldap-authentication/ldap-authentication_${jellyfinLdapPluginVersion}.zip";
    hash = "sha256-wjhsABvkOcmUYoCgLWJhDynjJdQJToO9MSId4/eqIK4=";
  };
  jellyfinEnhancedPluginVersion = "11.11.0.0";
  jellyfinEnhancedPluginZip = pkgs.fetchurl {
    url = "https://github.com/n00bcodr/Jellyfin-Enhanced/releases/download/${jellyfinEnhancedPluginVersion}/Jellyfin.Plugin.JellyfinEnhanced_10.11.0.zip";
    hash = "sha256-YmKWsQ4VyLO9cb2RxO2Q5A7TMq8BMWYcLsCEpoMGXNM=";
  };

  local = {
    adguard     = "127.0.0.1:3001";
    authelia    = "127.0.0.1:9091";
    lldapHttp   = "127.0.0.1:17170";
    lldapLdap   = "127.0.0.1:3890";
    grafana     = "127.0.0.1:3000";
    prometheus  = "127.0.0.1:9090";
    alertmanager = "127.0.0.1:9093";
    jellyfin    = "127.0.0.1:8096";
    jellyseerr  = "127.0.0.1:5055";
    radarr      = "127.0.0.1:7878";
    sonarr      = "127.0.0.1:8989";
    prowlarr    = "127.0.0.1:9696";
    bazarr      = "127.0.0.1:6767";
    qbittorrent = "127.0.0.1:8080";
  };

  mediaGroup = 1000;
  bazarrPackage = pkgs.bazarr.overrideAttrs (_old: rec {
    version = "1.5.6";
    src = pkgs.fetchzip {
      url = "https://github.com/morpheus65535/bazarr/releases/download/v${version}/bazarr.zip";
      hash = "sha256-S3idNH9Wm9f6aNj69dERmeks1rLvUeQJYFebXa5cWQo=";
      stripRoot = false;
    };
    buildInputs = [
      (pkgs.python3.withPackages (ps: [
        ps.lxml
        ps.numpy
        ps.gevent
        ps.gevent-websocket
        ps.pillow
        ps.setuptools
        ps.psycopg2
        ps.webrtcvad
      ]))
      pkgs.unar
      pkgs.ffmpeg
    ];
  });

  externalStorage = {
    enable = true;
    device = "/dev/disk/by-uuid/06d2efe6-c0b5-411c-8747-3a4ff0242979";
    mountPoint = "/srv/storage/external";
    fsType = "ext4";
    options = [
      "nofail"
      "x-systemd.automount"
      "x-systemd.idle-timeout=5min"
    ];
    media = {
      mountPoint = "/srv/media";
      source = "/srv/storage/external/media";
      fsType = "ext4";
      options = [
        "bind"
        "nofail"
        "x-systemd.requires-mounts-for=/srv/storage/external"
      ];
    };
    downloads = {
      mountPoint = "/srv/downloads";
      source = "/srv/storage/external/downloads";
      fsType = "ext4";
      options = [
        "bind"
        "nofail"
        "x-systemd.requires-mounts-for=/srv/storage/external"
      ];
    };
  };

  externalStoragePermissions = pkgs.writeShellApplication {
    name = "external-storage-permissions";
    runtimeInputs = [ pkgs.coreutils pkgs.findutils ];
    text = ''
      set -euo pipefail

      for path in /srv/media /srv/downloads; do
        [ -d "$path" ] || continue
        chown -R root:media "$path"
        find "$path" -type d -exec chmod 2775 {} +
        find "$path" -type f -exec chmod g+rw {} +
      done
    '';
  };

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

  mkAutheliaVhost =
    let
      backgroundPath = "/homelab-authelia-background.jpg";
      cssPath = "/homelab-authelia.css";
      base = mkVhost { backend = local.authelia; };
    in
      if !customAutheliaLogin then base else base // {
        locations = base.locations // {
          "= ${backgroundPath}" = {
            extraConfig = ''
              alias ${../../assets/authelia/background.jpg};
              default_type image/jpeg;
              add_header Cache-Control "public, max-age=300";
            '';
          };
          "= ${cssPath}" = {
            extraConfig = ''
              alias ${../../assets/authelia/homelab.css};
              default_type text/css;
              add_header Cache-Control "public, max-age=300";
            '';
          };
          "/" = base.locations."/" // {
            extraConfig = ''
              proxy_set_header Accept-Encoding "";
              sub_filter_once on;
              sub_filter_types text/html;
              sub_filter '</head>' '<link rel="stylesheet" href="${cssPath}"></head>';
            '';
          };
        };
      };

  mkJellyfinVhost = { backend, aliases ? [] }:
    let
      base = mkVhost { inherit backend aliases; };
    in
      base // {
        locations = base.locations // {
          "/" = base.locations."/" // {
            extraConfig = ''
              proxy_set_header Accept-Encoding "";
              sub_filter_once on;
              sub_filter_types text/html;
              sub_filter '</head>' '<script src="/JellyfinEnhanced/script"></script></head>';
            '';
          };
        };
      };

  jellyfinLdapSetup = pkgs.writeShellApplication {
    name = "jellyfin-ldap-setup";
    runtimeInputs = [ pkgs.coreutils pkgs.gnused pkgs.python3 pkgs.unzip ];
    text = ''
      set -euo pipefail

      plugin_dir="/var/lib/jellyfin/plugins/LDAP Authentication_${jellyfinLdapPluginVersion}"
      config_dir="/var/lib/jellyfin/plugins/configurations"
      system_config="/var/lib/jellyfin/config/system.xml"
      tmp="$(mktemp -d)"
      trap 'rm -rf "$tmp"' EXIT

      install -d -o jellyfin -g media -m 0700 /var/lib/jellyfin/plugins "$config_dir"
      for existing_plugin in /var/lib/jellyfin/plugins/LDAP\ Authentication_*; do
        [ -e "$existing_plugin" ] || continue
        [ "$existing_plugin" = "$plugin_dir" ] && continue
        rm -rf "$existing_plugin"
      done
      unzip -oq ${jellyfinLdapPluginZip} -d "$tmp"
      rm -rf "$plugin_dir"
      install -d -o jellyfin -g media -m 0700 "$plugin_dir"
      cp -R "$tmp"/. "$plugin_dir"/
      chown -R jellyfin:media "$plugin_dir"
      chmod -R u=rwX,go= "$plugin_dir"

      export LLDAP_ADMIN_PASSWORD_FILE="${config.sops.secrets.lldap-admin-password.path}"
      python3 - <<'PY'
      import os
      import xml.etree.ElementTree as ET
      from pathlib import Path

      config_dir = Path("/var/lib/jellyfin/plugins/configurations")
      config_dir.mkdir(parents=True, exist_ok=True)

      with open(os.environ["LLDAP_ADMIN_PASSWORD_FILE"], encoding="utf-8") as password_file:
          bind_password = password_file.read().strip()

      values = {
          "LdapServer": "127.0.0.1",
          "LdapPort": "3890",
          "AllowPassChange": "false",
          "UseSsl": "false",
          "UseStartTls": "false",
          "SkipSslVerify": "false",
          "LdapBindUser": "uid=admin,ou=people,${baseDn}",
          "LdapBindPassword": bind_password,
          "LdapBaseDn": "${baseDn}",
          "LdapSearchFilter": "(&(objectClass=person)(memberOf=cn=media,ou=groups,${baseDn}))",
          "LdapAdminBaseDn": "${baseDn}",
          "LdapAdminFilter": "(&(objectClass=person)(memberOf=cn=homelab_admins,ou=groups,${baseDn}))",
          "EnableLdapAdminFilterMemberUid": "false",
          "LdapSearchAttributes": "uid,mail,displayName,cn",
          "LdapClientCertPath": "",
          "LdapClientKeyPath": "",
          "LdapRootCaPath": "",
          "CreateUsersFromLdap": "true",
          "LdapUidAttribute": "uid",
          "LdapUsernameAttribute": "uid",
          "LdapPasswordAttribute": "userPassword",
          "EnableLdapProfileImageSync": "false",
          "RemoveImagesNotInLdap": "false",
          "LdapProfileImageAttribute": "jpegphoto",
          "LdapProfileImageFormat": "Default",
          "EnableAllFolders": "true",
          "PasswordResetUrl": "https://users.${domain}",
      }

      root = ET.Element(
          "PluginConfiguration",
          {
              "xmlns:xsi": "http://www.w3.org/2001/XMLSchema-instance",
              "xmlns:xsd": "http://www.w3.org/2001/XMLSchema",
          },
      )
      ET.SubElement(root, "LdapUsers")
      for key, value in values.items():
          child = ET.SubElement(root, key)
          child.text = value
      ET.SubElement(root, "EnabledFolders")

      tree = ET.ElementTree(root)
      ET.indent(tree, space="  ")
      tree.write(config_dir / "LDAP-Auth.xml", encoding="utf-8", xml_declaration=True)

      system_config = Path("/var/lib/jellyfin/config/system.xml")
      if system_config.exists():
          system_tree = ET.parse(system_config)
          system_root = system_tree.getroot()
          wizard = system_root.find("IsStartupWizardCompleted")
          if wizard is None:
              wizard = ET.SubElement(system_root, "IsStartupWizardCompleted")
          wizard.text = "true"
          ET.indent(system_tree, space="  ")
          system_tree.write(system_config, encoding="utf-8", xml_declaration=True)
      PY

      chown jellyfin:media "$config_dir/LDAP-Auth.xml" "$system_config"
      chmod 0600 "$config_dir/LDAP-Auth.xml" "$system_config"
    '';
  };

  jellyfinEnhancedSetup = pkgs.writeShellApplication {
    name = "jellyfin-enhanced-setup";
    runtimeInputs = [ pkgs.coreutils pkgs.findutils pkgs.python3 pkgs.unzip ];
    text = ''
      set -euo pipefail

      plugin_dir="/var/lib/jellyfin/plugins/Jellyfin Enhanced_${jellyfinEnhancedPluginVersion}"
      config_dir="/var/lib/jellyfin/plugins/configurations"
      config_file="$config_dir/Jellyfin.Plugin.JellyfinEnhanced.xml"
      jellyseerr_settings="/var/lib/private/jellyseerr/config/settings.json"
      tmp="$(mktemp -d)"
      trap 'rm -rf "$tmp"' EXIT

      install -d -o jellyfin -g media -m 0700 /var/lib/jellyfin/plugins "$config_dir"
      for existing_plugin in /var/lib/jellyfin/plugins/Jellyfin\ Enhanced_*; do
        [ -e "$existing_plugin" ] || continue
        [ "$existing_plugin" = "$plugin_dir" ] && continue
        rm -rf "$existing_plugin"
      done

      unzip -oq ${jellyfinEnhancedPluginZip} -d "$tmp"
      rm -rf "$plugin_dir"
      install -d -o jellyfin -g media -m 0700 "$plugin_dir"
      cp -R "$tmp"/. "$plugin_dir"/
      chown -R jellyfin:media "$plugin_dir"
      chmod -R u=rwX,go= "$plugin_dir"

      JELLYSEERR_API_KEY=""
      if [ -f "$jellyseerr_settings" ]; then
        JELLYSEERR_API_KEY="$(python3 - <<'PY'
      import json
      from pathlib import Path

      settings = Path("/var/lib/private/jellyseerr/config/settings.json")
      try:
          data = json.loads(settings.read_text(encoding="utf-8"))
      except (OSError, json.JSONDecodeError):
          print("")
      else:
          print(data.get("main", {}).get("apiKey", ""))
      PY
      )"
      fi
      export JELLYSEERR_API_KEY

      python3 - <<'PY'
      import os
      import xml.etree.ElementTree as ET
      from pathlib import Path

      values = {
          "JellyseerrEnabled": "true",
          "JellyseerrShowSearchResults": "true",
          "JellyseerrShowReportButton": "false",
          "JellyseerrShowIssueIndicator": "true",
          "JellyseerrEnable4KRequests": "false",
          "JellyseerrEnable4KTvRequests": "false",
          "JellyseerrShowAdvanced": "false",
          "JellyseerrShowQuotaInfo": "true",
          "JellyseerrShowSimilar": "true",
          "JellyseerrShowRecommended": "true",
          "JellyseerrShowRequestMoreOnSeries": "true",
          "JellyseerrShowNetworkDiscovery": "true",
          "JellyseerrShowGenreDiscovery": "true",
          "JellyseerrShowTagDiscovery": "true",
          "JellyseerrShowPersonDiscovery": "true",
          "JellyseerrShowCollectionDiscovery": "true",
          "JellyseerrExcludeLibraryItems": "true",
          "JellyseerrExcludeBlocklistedItems": "false",
          "JellyseerrUseMoreInfoModal": "false",
          "JellyseerrUrls": "https://catalog.${domain}",
          "JellyseerrApiKey": os.environ.get("JELLYSEERR_API_KEY", ""),
          "JellyseerrUrlMappings": "",
          "JellyseerrAutoImportUsers": "true",
          "JellyseerrImportBlockedUsers": "",
          "JellyseerrDisableCache": "false",
          "JellyseerrResponseCacheTtlMinutes": "10",
          "JellyseerrUserIdCacheTtlMinutes": "30",
          "TriggerSeerrScanOnItemAdded": "true",
          "SeerrScanDebounceSeconds": "60",
          "AddRequestedMediaToWatchlist": "true",
          "SyncJellyseerrWatchlist": "false",
          "PreventWatchlistReAddition": "true",
          "WatchlistMemoryRetentionDays": "365",
          "ShowCollectionsInSearch": "true",
      }

      root = ET.Element(
          "PluginConfiguration",
          {
              "xmlns:xsi": "http://www.w3.org/2001/XMLSchema-instance",
              "xmlns:xsd": "http://www.w3.org/2001/XMLSchema",
          },
      )
      for key, value in values.items():
          child = ET.SubElement(root, key)
          child.text = value

      config_file = Path("/var/lib/jellyfin/plugins/configurations/Jellyfin.Plugin.JellyfinEnhanced.xml")
      tree = ET.ElementTree(root)
      ET.indent(tree, space="  ")
      tree.write(config_file, encoding="utf-8", xml_declaration=True)
      PY

      chown jellyfin:media "$config_file"
      chmod 0600 "$config_file"
    '';
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

  fileSystems = lib.optionalAttrs externalStorage.enable {
    ${externalStorage.mountPoint} = {
      device = externalStorage.device;
      fsType = externalStorage.fsType;
      options = externalStorage.options;
    };
    ${externalStorage.media.mountPoint} = {
      device = externalStorage.media.source;
      fsType = "none";
      options = externalStorage.media.options;
    };
    ${externalStorage.downloads.mountPoint} = {
      device = externalStorage.downloads.source;
      fsType = "none";
      options = externalStorage.downloads.options;
    };
  };

  systemd.tmpfiles.rules = [
    "d /srv/homelab 0755 root root -"
    "d /srv/media 2775 root media -"
    "d /srv/media/movies 2775 root media -"
    "d /srv/media/tv 2775 root media -"
    "d /srv/storage 0755 root root -"
    "d /srv/storage/external 0755 root root -"
    "d /srv/downloads 2775 root media -"
    "d /srv/downloads/complete 2775 root media -"
    "d /srv/downloads/incomplete 2775 root media -"
    "d /var/log/authelia 0750 authelia-main authelia-main -"
  ];

  systemd.services.external-storage-permissions = lib.mkIf externalStorage.enable {
    description = "Normalize external media SSD ownership";
    after = [
      "srv-media.mount"
      "srv-downloads.mount"
    ];
    requires = [
      "srv-media.mount"
      "srv-downloads.mount"
    ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${externalStoragePermissions}/bin/external-storage-permissions";
    };
  };

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
  sops.secrets."lldap-user-angela-password" = {
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
  sops.secrets.bazarr-opensubtitlescom-username = {
    sopsFile = ../../secrets/bazarr.yaml;
    owner = "bazarr";
    group = "bazarr";
    mode = "0400";
    restartUnits = [ "bazarr.service" ];
  };
  sops.secrets.bazarr-opensubtitlescom-password = {
    sopsFile = ../../secrets/bazarr.yaml;
    owner = "bazarr";
    group = "bazarr";
    mode = "0400";
    restartUnits = [ "bazarr.service" ];
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
      "auth.${domain}" = mkAutheliaVhost // { serverAliases = [ "sso.${domain}" ]; };
      "users.${domain}" = mkVhost { backend = local.lldapHttp; };
      "adguard.${domain}" = mkVhost { backend = local.adguard; sso = true; aliases = [ "dns.${domain}" ]; };
      "${domain}" = mkVhost { backend = local.grafana; sso = true; };
      "grafana.${domain}" = mkVhost { backend = local.grafana; sso = true; aliases = [ "status.${domain}" ]; };
      "prometheus.${domain}" = mkVhost { backend = local.prometheus; sso = true; aliases = [ "metrics.${domain}" ]; };
      "alerts.${domain}" = mkVhost { backend = local.alertmanager; sso = true; };
      "jellyfin.${domain}" = mkJellyfinVhost { backend = local.jellyfin; aliases = [ "watch.${domain}" ]; };
      "jellyseerr.${domain}" = mkVhost { backend = local.jellyseerr; aliases = [ "catalog.${domain}" ]; };
      "radarr.${domain}" = mkVhost { backend = local.radarr; sso = true; aliases = [ "movies.${domain}" ]; };
      "sonarr.${domain}" = mkVhost { backend = local.sonarr; sso = true; aliases = [ "tv.${domain}" ]; };
      "prowlarr.${domain}" = mkVhost { backend = local.prowlarr; sso = true; aliases = [ "indexers.${domain}" ]; };
      "bazarr.${domain}" = mkVhost { backend = local.bazarr; sso = true; aliases = [ "subtitles.${domain}" ]; };
      "qbittorrent.${domain}" = mkVhost { backend = local.qbittorrent; sso = true; aliases = [ "torrents.${domain}" ]; };
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
        { name = "homelab_admins"; displayName = "Homelab Admins"; }
        { name = "media"; displayName = "Media Users"; }
      ];
      users = [
        {
          username = "drew";
          email = "drewnorman739@gmail.com";
          displayName = "Drew Norman";
          groups = [ "lldap_strict_readonly" "homelab_admins" "media" ];
          passwordFile = config.sops.secrets."lldap-user-drew-password".path;
        }
        {
          username = "angela";
          email = "angela@${domain}";
          displayName = "Angela";
          groups = [ "media" ];
          passwordFile = config.sops.secrets."lldap-user-angela-password".path;
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
      theme = "auto";
      server = {
        address = "tcp://127.0.0.1:9091";
      } // lib.optionalAttrs customAutheliaLogin {
        asset_path = ../../assets/authelia;
      };
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
      access_control = {
        default_policy = "deny";
        rules = [
          {
            domain = [
              "users.${domain}"
              "adguard.${domain}"
              "dns.${domain}"
              domain
              "grafana.${domain}"
              "status.${domain}"
              "prometheus.${domain}"
              "metrics.${domain}"
              "alerts.${domain}"
              "prowlarr.${domain}"
              "indexers.${domain}"
            ];
            policy = "one_factor";
            subject = [ "group:homelab_admins" ];
          }
          {
            domain = [
              "radarr.${domain}"
              "movies.${domain}"
              "sonarr.${domain}"
              "tv.${domain}"
              "bazarr.${domain}"
              "subtitles.${domain}"
              "qbittorrent.${domain}"
              "torrents.${domain}"
            ];
            policy = "one_factor";
            subject = [ "group:media" ];
          }
        ];
      };
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
      auth = {
        disable_login_form = true;
        disable_signout_menu = true;
      };
      "auth.proxy" = {
        enabled = true;
        header_name = "Remote-User";
        header_property = "username";
        auto_sign_up = true;
        whitelist = "127.0.0.1";
        headers = "Name:Remote-Name Email:Remote-Email Groups:Remote-Groups";
      };
      users = {
        allow_sign_up = false;
        auto_assign_org_role = "Admin";
      };
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
    package = pkgsJellyfin.jellyfin;
    openFirewall = false;
    group = "media";
  };
  systemd.services.jellyfin = {
    after = [ "lldap-provision.service" ];
    requires = [ "lldap-provision.service" ];
    serviceConfig.ExecStartPre = [
      "+${jellyfinLdapSetup}/bin/jellyfin-ldap-setup"
      "+${jellyfinEnhancedSetup}/bin/jellyfin-enhanced-setup"
    ];
  };

  services.jellyseerr = {
    enable = true;
    openFirewall = false;
  };

  systemd.services.radarr.preStart = ''
    cfg=/var/lib/radarr/.config/Radarr/config.xml
    if [ -f "$cfg" ]; then
      ${pkgs.xmlstarlet}/bin/xmlstarlet ed -L \
        -u "/Config/AuthenticationMethod[1]" -v "External" \
        -d "/Config/AuthenticationMethod[position()>1]" \
        -u "/Config/AuthenticationRequired[1]" -v "DisabledForLocalAddresses" \
        -d "/Config/AuthenticationRequired[position()>1]" \
        "$cfg"
    fi
  '';
  systemd.services.sonarr.preStart = ''
    cfg=/var/lib/sonarr/.config/NzbDrone/config.xml
    if [ -f "$cfg" ]; then
      ${pkgs.xmlstarlet}/bin/xmlstarlet ed -L \
        -u "/Config/AuthenticationMethod[1]" -v "External" \
        -d "/Config/AuthenticationMethod[position()>1]" \
        -u "/Config/AuthenticationRequired[1]" -v "DisabledForLocalAddresses" \
        -d "/Config/AuthenticationRequired[position()>1]" \
        "$cfg"
    fi
  '';

  services.radarr = { enable = true; group = "media"; openFirewall = false; };
  services.sonarr = { enable = true; group = "media"; openFirewall = false; };
  services.prowlarr = { enable = true; openFirewall = false; };
  services.bazarr = { enable = true; package = bazarrPackage; openFirewall = false; };
  systemd.services.bazarr = {
    after = [ "radarr.service" "sonarr.service" ];
    wants = [ "radarr.service" "sonarr.service" ];
    preStart = ''
      set -euo pipefail

      cfg=/var/lib/bazarr/config/config.yaml
      db=/var/lib/bazarr/db/bazarr.db
      radarr_cfg=/var/lib/radarr/.config/Radarr/config.xml
      sonarr_cfg=/var/lib/sonarr/.config/NzbDrone/config.xml
      opensubtitlescom_username_file=/run/secrets/bazarr-opensubtitlescom-username
      opensubtitlescom_password_file=/run/secrets/bazarr-opensubtitlescom-password
      subdl_api_key_file=/run/secrets/bazarr-subdl-api-key
      addic7ed_username_file=/run/secrets/bazarr-addic7ed-username
      addic7ed_password_file=/run/secrets/bazarr-addic7ed-password

      [ -f "$cfg" ] || exit 0
      [ -f "$radarr_cfg" ] || exit 0
      [ -f "$sonarr_cfg" ] || exit 0

      radarr_apikey="$(${pkgs.xmlstarlet}/bin/xmlstarlet sel -t -v '/Config/ApiKey' "$radarr_cfg")"
      sonarr_apikey="$(${pkgs.xmlstarlet}/bin/xmlstarlet sel -t -v '/Config/ApiKey' "$sonarr_cfg")"
      opensubtitlescom_username=""
      opensubtitlescom_password=""
      subdl_api_key=""
      addic7ed_username=""
      addic7ed_password=""

      if [ -f "$opensubtitlescom_username_file" ] \
        && [ -f "$opensubtitlescom_password_file" ]; then
        opensubtitlescom_username="$(cat "$opensubtitlescom_username_file")"
        opensubtitlescom_password="$(cat "$opensubtitlescom_password_file")"
      fi
      if [ -f "$subdl_api_key_file" ]; then
        subdl_api_key="$(cat "$subdl_api_key_file")"
      fi
      if [ -f "$addic7ed_username_file" ] \
        && [ -f "$addic7ed_password_file" ]; then
        addic7ed_username="$(cat "$addic7ed_username_file")"
        addic7ed_password="$(cat "$addic7ed_password_file")"
      fi

      export BAZARR_CONFIG="$cfg"
      export BAZARR_DB="$db"
      export RADARR_APIKEY="$radarr_apikey"
      export SONARR_APIKEY="$sonarr_apikey"
      export OPENSUBTITLESCOM_USERNAME="$opensubtitlescom_username"
      export OPENSUBTITLESCOM_PASSWORD="$opensubtitlescom_password"
      export SUBDL_API_KEY="$subdl_api_key"
      export ADDIC7ED_USERNAME="$addic7ed_username"
      export ADDIC7ED_PASSWORD="$addic7ed_password"

      ${pkgs.python3.withPackages (ps: [ ps.pyyaml ])}/bin/python3 <<'PY'
      import json
      import os
      import sqlite3
      from pathlib import Path

      import yaml

      config_path = Path(os.environ["BAZARR_CONFIG"])
      db_path = Path(os.environ["BAZARR_DB"])

      with config_path.open() as fh:
          config = yaml.safe_load(fh) or {}

      general = config.setdefault("general", {})
      enabled_providers = ["embeddedsubtitles", "gestdown"]
      if all((
          os.environ["OPENSUBTITLESCOM_USERNAME"],
          os.environ["OPENSUBTITLESCOM_PASSWORD"],
      )):
          enabled_providers.append("opensubtitlescom")
      if os.environ["SUBDL_API_KEY"]:
          enabled_providers.append("subdl")
      if all((
          os.environ["ADDIC7ED_USERNAME"],
          os.environ["ADDIC7ED_PASSWORD"],
      )):
          enabled_providers.append("addic7ed")

      general.update({
          "enabled_providers": enabled_providers,
          "movie_default_enabled": True,
          "movie_default_profile": 1,
          "serie_default_enabled": True,
          "serie_default_profile": 1,
          "upgrade_subs": False,
          "use_radarr": True,
          "use_sonarr": True,
      })

      radarr = config.setdefault("radarr", {})
      radarr.update({
          "apikey": os.environ["RADARR_APIKEY"],
          "base_url": "/",
          "ip": "127.0.0.1",
          "port": 7878,
          "ssl": False,
      })

      sonarr = config.setdefault("sonarr", {})
      sonarr.update({
          "apikey": os.environ["SONARR_APIKEY"],
          "base_url": "/",
          "ip": "127.0.0.1",
          "port": 8989,
          "ssl": False,
      })

      config.setdefault("podnapisi", {})["verify_ssl"] = True
      config.setdefault("embeddedsubtitles", {}).update({
          "fallback_lang": "en",
          "included_codecs": [],
          "timeout": 600,
      })
      config.setdefault("opensubtitlescom", {}).update({
          "username": os.environ["OPENSUBTITLESCOM_USERNAME"],
          "password": os.environ["OPENSUBTITLESCOM_PASSWORD"],
          "use_hash": True,
          "include_ai_translated": False,
      })
      config.setdefault("subdl", {}).update({
          "api_key": os.environ["SUBDL_API_KEY"],
      })
      config.setdefault("addic7ed", {}).update({
          "username": os.environ["ADDIC7ED_USERNAME"],
          "password": os.environ["ADDIC7ED_PASSWORD"],
          "cookies": "",
          "user_agent": "",
          "vip": False,
      })

      with config_path.open("w") as fh:
          yaml.safe_dump(config, fh, default_flow_style=False, sort_keys=False)

      if db_path.exists():
          profile_items = json.dumps([{
              "id": 1,
              "language": "en",
              "forced": "False",
              "hi": "False",
              "audio_exclude": "False",
          }])
          with sqlite3.connect(db_path) as con:
              con.execute(
                  """
                  insert into table_languages_profiles
                    (profileId, cutoff, originalFormat, items, name, mustContain, mustNotContain, tag)
                  values (?, ?, ?, ?, ?, ?, ?, ?)
                  on conflict(profileId) do update set
                    cutoff = excluded.cutoff,
                    originalFormat = excluded.originalFormat,
                    items = excluded.items,
                    name = excluded.name,
                    mustContain = excluded.mustContain,
                    mustNotContain = excluded.mustNotContain,
                    tag = excluded.tag
                  """,
                  (1, None, None, profile_items, "English", "[]", "[]", None),
              )
              con.execute("update table_settings_languages set enabled = 1 where code2 = 'en'")
              con.execute("update table_shows set profileId = 1 where profileId is null")
              con.execute("update table_movies set profileId = 1 where profileId is null")
      PY

      chown bazarr:bazarr "$cfg"
      [ ! -f "$db" ] || chown bazarr:bazarr "$db"
    '';
  };
  users.users.bazarr.extraGroups = [ "media" ];

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
      set_pref() {
        key="$1"
        value="$2"
        tmp="$(mktemp)"
        found=0
        while IFS= read -r line; do
          case "''${line%%=*}" in
            WebUILocalHostAuth|WebUIAuthSubnetWhitelist|WebUIAuthSubnetWhitelistEnabled|WebUIUseUPnP)
              continue
              ;;
          esac
          if [ "''${line%%=*}" = "$key" ]; then
            printf '%s=%s\n' "$key" "$value"
            found=1
          else
            printf '%s\n' "$line"
          fi
        done < "$cfg" > "$tmp"
        if [ "$found" -eq 0 ]; then
          printf '%s=%s\n' "$key" "$value" >> "$tmp"
        fi
        cat "$tmp" > "$cfg"
        rm -f "$tmp"
      }

      if [ ! -f "$cfg" ]; then
        mkdir -p "$(dirname "$cfg")"
        cat > "$cfg" <<'EOF'
[BitTorrent]
Session\DefaultSavePath=/srv/downloads/
Session\TempPath=/srv/downloads/incomplete/
[Preferences]
EOF
      fi
      set_pref 'WebUI\LocalHostAuth' 'false'
      set_pref 'WebUI\AuthSubnetWhitelist' '127.0.0.1/32,192.168.1.0/24'
      set_pref 'WebUI\AuthSubnetWhitelistEnabled' 'true'
      set_pref 'WebUI\UseUPnP' 'false'
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
