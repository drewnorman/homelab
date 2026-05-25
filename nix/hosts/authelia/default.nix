{ config, lib, pkgs, allHosts, ... }:

let
  domain  = "lab.adre.me";
  baseDn  = "dc=lab,dc=adre,dc=me";
in
{
  networking.firewall.allowedTCPPorts = [ 9091 ];

  sops.secrets.authelia-jwt-secret = {
    sopsFile = ../../secrets/authelia.yaml;
    owner    = "authelia-main";
  };
  sops.secrets.authelia-session-secret = {
    sopsFile = ../../secrets/authelia.yaml;
    owner    = "authelia-main";
  };
  sops.secrets.authelia-storage-encryption-key = {
    sopsFile = ../../secrets/authelia.yaml;
    owner    = "authelia-main";
  };
  sops.secrets.authelia-lldap-password = {
    sopsFile = ../../secrets/authelia.yaml;
    owner    = "authelia-main";
  };
  sops.secrets.tailscale-auth-key = {
    sopsFile = ../../secrets/authelia.yaml;
    owner    = "root";
  };

  services.authelia.instances.main = {
    enable = true;

    secrets = {
      jwtSecretFile            = config.sops.secrets.authelia-jwt-secret.path;
      sessionSecretFile        = config.sops.secrets.authelia-session-secret.path;
      storageEncryptionKeyFile = config.sops.secrets.authelia-storage-encryption-key.path;
    };

    settings = {
      theme                     = "dark";
      default_redirection_url   = "https://${domain}";

      server.address = "tcp://0.0.0.0:9091";

      log = {
        level         = "info";
        keep_stdout   = true;
      };

      totp = {
        issuer = domain;
        period = 30;
        skew   = 1;
      };

      authentication_backend.ldap = {
        implementation = "lldap";
        address        = "ldap://${allHosts.lldap.ip}:3890";
        base_dn        = baseDn;
        user           = "uid=admin,ou=people,${baseDn}";
        # password is injected via AUTHELIA_AUTHENTICATION_BACKEND_LDAP_PASSWORD_FILE
        # below — do not set it here or the path string becomes the literal password.
      };

      access_control.default_policy = "one_factor";

      session.cookies = [
        {
          name         = "authelia_session";
          domain       = domain;
          authelia_url = "https://auth.${domain}";
          expiration   = "12h";
          inactivity   = "1h";
          remember_me  = "1M";
        }
      ];

      regulation = {
        max_retries = 5;
        find_time   = "5m";
        ban_time    = "15m";
      };

      storage.local.path = "/var/lib/authelia-main/db.sqlite3";

      notifier.filesystem.filename = "/var/log/authelia/notification.txt";
    };
  };

  # Authelia's secret-file env var mechanism: reads the LDAP password from the
  # sops-managed file rather than embedding the path string in the YAML config.
  systemd.services."authelia-main".environment = {
    AUTHELIA_AUTHENTICATION_BACKEND_LDAP_PASSWORD_FILE =
      config.sops.secrets.authelia-lldap-password.path;
  };

  services.tailscale.authKeyFile = config.sops.secrets.tailscale-auth-key.path;

  systemd.tmpfiles.rules = [
    "d /var/log/authelia 0750 authelia-main authelia-main -"
  ];
}
