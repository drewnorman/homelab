# Shared base configuration for the consolidated NixOS VM.
{ lib, pkgs, sshAuthorizedKeys, hostMeta, flakeAttr, modulesPath, ... }:
{
  imports = [
    "${modulesPath}/profiles/qemu-guest.nix"
  ];

  networking.hostName = hostMeta.hostname;

  boot.loader.grub = {
    enable = lib.mkDefault true;
    device = lib.mkDefault (hostMeta.bootDevice or "/dev/sda");
  };

  fileSystems."/" = {
    device = lib.mkDefault (hostMeta.rootDevice or "/dev/disk/by-label/nixos");
    fsType = lib.mkDefault (hostMeta.rootFsType or "ext4");
  };

  services.qemuGuest.enable = true;

  networking.useDHCP = false;
  networking.interfaces.${hostMeta.networkInterface or "ens18"}.ipv4.addresses = [
    {
      address      = hostMeta.ip;
      prefixLength = 24;
    }
  ];
  networking.defaultGateway = "192.168.1.1";
  networking.nameservers    = [ "192.168.1.1" "1.1.1.1" ];

  nix = {
    settings = {
      experimental-features = [ "nix-command" "flakes" ];
      auto-optimise-store   = true;
      substituters          = [ "https://cache.nixos.org" ];
      trusted-public-keys   = [ "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY=" ];
    };
    gc = {
      automatic = true;
      dates     = "weekly";
      options   = "--delete-older-than 14d";
    };
  };

  time.timeZone = "America/Denver";
  i18n.defaultLocale = "en_US.UTF-8";

  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin        = "prohibit-password";
      PasswordAuthentication = false;
    };
    hostKeys = [
      { type = "ed25519"; path = "/etc/ssh/ssh_host_ed25519_key"; }
      { type = "rsa"; bits = 4096; path = "/etc/ssh/ssh_host_rsa_key"; }
    ];
  };

  users.users = {
    root.openssh.authorizedKeys.keys = sshAuthorizedKeys;
    drew = {
      isNormalUser = true;
      extraGroups = [ "wheel" ];
      openssh.authorizedKeys.keys = sshAuthorizedKeys;
    };
  };
  sops.age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];

  networking.firewall = {
    enable            = true;
    trustedInterfaces = [ "tailscale0" ];
    allowedTCPPorts   = [ 22 80 443 ];
    allowedUDPPorts   = [ 53 ];
    checkReversePath  = "loose";
  };

  services.prometheus.exporters.node = {
    enable = true;
    enabledCollectors = [ "systemd" ];
    openFirewall = false;
  };

  environment.systemPackages = with pkgs; [
    curl
    htop
    iproute2
    vim
  ];

  system.autoUpgrade = {
    enable = false;
    flake  = "github:drewnorman/homelab?dir=nix#${flakeAttr}";
    flags  = [ "--accept-flake-config" ];
  };

  system.stateVersion = "25.05";
}
