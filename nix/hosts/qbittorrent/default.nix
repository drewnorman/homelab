# qBittorrent with Proton VPN WireGuard kill switch.
#
# The nftables rules drop all traffic that isn't going through the VPN tunnel,
# so qBittorrent can only reach the internet via Proton VPN. LAN traffic
# (Caddy reverse proxy, arr apps) is explicitly allowed.
{ config, lib, pkgs, ... }:

let
  vpnInterface  = "wg0";
  listenPort    = 6881;
  qbtPort       = 8080;
  lanCidr       = "192.168.1.0/24";
in
{
  networking.firewall.allowedTCPPorts = [ qbtPort ];

  # Proton VPN WireGuard config — store private key + config in sops
  sops.secrets.protonvpn-wireguard-config = {
    sopsFile = ../../secrets/qbittorrent.yaml;
    path     = "/etc/wireguard/${vpnInterface}.conf";
    mode     = "0600";
  };

  # WireGuard VPN interface
  networking.wg-quick.interfaces.${vpnInterface} = {
    # The actual config file is written by sops-nix; wg-quick reads it.
    configFile = config.sops.secrets.protonvpn-wireguard-config.path;
    # PostUp/PreDown hooks to reload nftables when the interface changes.
    postUp   = "systemctl reload nftables || true";
    preDown  = "systemctl reload nftables || true";
  };

  # nftables kill switch — block all non-VPN internet traffic
  networking.nftables = {
    enable = true;
    ruleset = ''
      table inet kill_switch {
        chain output {
          type filter hook output priority 0; policy accept;

          # Allow loopback
          oifname "lo" accept

          # Allow LAN traffic (reverse proxy access from Caddy, arr sync)
          ip daddr ${lanCidr} accept

          # Allow established/related (incoming from VPN tunnel)
          ct state established,related accept

          # Allow traffic on the VPN tunnel itself
          oifname "${vpnInterface}" accept

          # Allow DNS on LAN interface (for initial VPN handshake)
          ip daddr ${lanCidr} udp dport 53 accept

          # Block everything else going out to the internet
          oifname != "${vpnInterface}" ip daddr != ${lanCidr} drop
        }
      }
    '';
  };

  # qBittorrent — bind traffic to the VPN interface only
  services.qbittorrent = {
    enable    = true;
    openFirewall = false;
    # Ensure qBittorrent starts only after WireGuard and nftables are up
    after     = [ "wg-quick-${vpnInterface}.service" "nftables.service" ];
    requires  = [ "wg-quick-${vpnInterface}.service" "nftables.service" ];
  };

  users.groups.media = { gid = 1000; };

  # qBittorrent must be in the media group to write to the shared download path.
  users.users.qbittorrent = {
    extraGroups = [ "media" ];
  };

  systemd.tmpfiles.rules = [
    "d /mnt/media                     2775 root        media -"
    "d /srv/downloads                  2775 root        media -"
    "d /srv/downloads/complete         2775 root        media -"
    "d /srv/downloads/complete/movies  2775 root        media -"
    "d /srv/downloads/complete/tv      2775 root        media -"
    "d /srv/downloads/incomplete       2775 root        media -"
  ];
}
