{ config, lib, pkgs, ... }:
{
  networking.firewall.allowedTCPPorts = [ 8080 ];

  users.users.qbittorrent = {
    isSystemUser = true;
    group        = "qbittorrent";
    home         = "/var/lib/qbittorrent";
  };
  users.groups.qbittorrent = {};

  # Ensure /srv/downloads exists for when the bind mount is not configured.
  systemd.tmpfiles.rules = [
    "d /srv/downloads            0775 qbittorrent qbittorrent -"
    "d /srv/downloads/incomplete 0775 qbittorrent qbittorrent -"
  ];

  systemd.services.qbittorrent = {
    description = "qBittorrent-nox download client";
    after       = [ "network.target" ];
    wantedBy    = [ "multi-user.target" ];
    # Write an initial config on first start so arr categories resolve to the
    # right paths. Config is preserved in /persist so webui changes survive.
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
      User           = "qbittorrent";
      Group          = "qbittorrent";
      ExecStart      = "${pkgs.qbittorrent-nox}/bin/qbittorrent-nox --webui-port=8080 --profile=/var/lib/qbittorrent";
      Restart        = "on-failure";
      StateDirectory = "qbittorrent";
    };
  };

  environment.persistence."/persist" = {
    directories = [ "/var/lib/qbittorrent" ];
  };
}
