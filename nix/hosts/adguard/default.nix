{ config, lib, pkgs, allHosts, ... }:
{
  networking.firewall.allowedTCPPorts = [ 80 ];
  networking.firewall.allowedUDPPorts = [ 53 ];

  services.adguardhome = {
    enable      = true;
    openFirewall = true;

    # mutableSettings = true means these settings seed the initial config and
    # AdGuard manages subsequent changes. Set to false for fully declarative
    # control, but then users/passwords must also be declared here.
    mutableSettings = true;

    settings = {
      bind_host = "0.0.0.0";
      bind_port = 80;

      dns = {
        bind_hosts   = [ "0.0.0.0" ];
        port         = 53;
        upstream_dns = [ "https://dns.cloudflare.com/dns-query" ];
        bootstrap_dns = [
          "9.9.9.10"
          "149.112.112.10"
          "2620:fe::10"
          "2620:fe::fe:10"
        ];
        fallback_dns  = [ "https://dns.google/dns-query" ];
        blocked_hosts = [ "version.bind" "id.server" "hostname.bind" ];
      };

      filtering = {
        rewrites = [
          # Wildcard *.lab.adre.me and the apex both resolve to the edge proxy
          { domain = "lab.adre.me";   answer = allHosts.edge.ip; }
          { domain = "*.lab.adre.me"; answer = allHosts.edge.ip; }
        ];
      };

      filters = [
        { enabled = true;  id = 1;          url = "https://adguardteam.github.io/HostlistsRegistry/assets/filter_1.txt"; name = "AdGuard DNS filter"; }
        { enabled = false; id = 2;          url = "https://adguardteam.github.io/HostlistsRegistry/assets/filter_2.txt"; name = "AdAway Default Blocklist"; }
        { enabled = true;  id = 1776125343; url = "https://small.oisd.nl/";                                                           name = "OISD Small"; }
        { enabled = true;  id = 1776125344; url = "https://cdn.jsdelivr.net/gh/hagezi/dns-blocklists@latest/adblock/pro.plus.txt";  name = "HaGeZi Pro++"; }
        { enabled = true;  id = 1776125345; url = "https://cdn.jsdelivr.net/gh/hagezi/dns-blocklists@latest/adblock/tif.txt";       name = "HaGeZi TIF"; }
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
}
