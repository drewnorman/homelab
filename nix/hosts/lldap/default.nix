{ config, lib, pkgs, ... }:
{
  networking.firewall.allowedTCPPorts = [ 3890 17170 ];

  sops.secrets.lldap-jwt-secret = {
    sopsFile = ../../secrets/lldap.yaml;
    owner    = "lldap";
  };
  sops.secrets.lldap-admin-password = {
    sopsFile = ../../secrets/lldap.yaml;
    owner    = "lldap";
  };
  # One sops secret per user password; add a key to lldap.yaml for each.
  sops.secrets."lldap-user-drew-password" = {
    sopsFile = ../../secrets/lldap.yaml;
    owner    = "lldap";
  };

  services.lldap = {
    enable = true;

    settings = {
      http_port    = 17170;
      ldap_port    = 3890;
      ldap_base_dn = "dc=lab,dc=adre,dc=me";
      http_url     = "https://users.lab.adre.me";
    };

    environment = {
      LLDAP_JWT_SECRET_FILE     = config.sops.secrets.lldap-jwt-secret.path;
      LLDAP_LDAP_USER_PASS_FILE = config.sops.secrets.lldap-admin-password.path;
    };

    provision = {
      enable            = true;
      adminPasswordFile = config.sops.secrets.lldap-admin-password.path;

      groups = [
        { name = "lldap_strict_readonly"; displayName = "LLDAP Read-Only"; }
        { name = "media";                 displayName = "Media Users"; }
      ];

      users = [
        {
          username     = "drew";
          email        = "drewnorman739@gmail.com";
          displayName  = "Drew Norman";
          groups       = [ "lldap_strict_readonly" "media" ];
          passwordFile = config.sops.secrets."lldap-user-drew-password".path;
        }
        # Add more users here and run:
        #   nixos-rebuild switch --flake .#lldap --target-host root@192.168.1.214
        # Add a sops.secrets."lldap-user-<name>-password" entry for each new user.
      ];
    };
  };
}
