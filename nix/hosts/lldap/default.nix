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

  services.lldap = {
    enable = true;

    settings = {
      http_port  = 17170;
      ldap_port  = 3890;
      ldap_base_dn = "dc=lab,dc=adre,dc=me";
      http_url   = "https://users.lab.adre.me";
    };

    # Secrets are passed as environment variables via the environment file.
    # sops-nix writes the secret values to files; we render an env file in the
    # activation script so the service picks them up on start.
    environment = {
      LLDAP_JWT_SECRET_FILE      = config.sops.secrets.lldap-jwt-secret.path;
      LLDAP_LDAP_USER_PASS_FILE  = config.sops.secrets.lldap-admin-password.path;
    };
  };
}
