# Shared base configuration for all homelab NixOS LXC containers.
# Each host imports this module; per-service config lives in hosts/<name>/.
{ lib, pkgs, sshAuthorizedKeys, hostMeta, flakeAttr, ... }:
{
  networking.hostName = hostMeta.hostname;

  # Proxmox LXC — no bootloader, no initrd
  boot.isContainer = true;

  # Static networking via classic ip-based setup rather than systemd-networkd.
  # networkd fails in unprivileged LXC (systemd 258+ credential loading is
  # blocked by the container security profile); the classic path uses ip(8)
  # directly and works fine.
  networking.useDHCP = false;
  networking.useNetworkd = false;
  networking.interfaces.veth0.ipv4.addresses = [{
    address      = hostMeta.ip;
    prefixLength = 24;
  }];
  networking.defaultGateway  = "192.168.1.1";
  networking.nameservers     = [ "192.168.1.1" "1.1.1.1" ];

  # Nix
  nix = {
    settings = {
      experimental-features = [ "nix-command" "flakes" ];
      auto-optimise-store   = true;
      # Use the NixOS cache so builds resolve fast on the first deploy
      substituters      = [ "https://cache.nixos.org" ];
      trusted-public-keys = [ "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY=" ];
    };
    gc = {
      automatic = true;
      dates     = "weekly";
      options   = "--delete-older-than 14d";
    };
  };

  # Time
  time.timeZone = "America/Denver";

  # Locale (keep minimal — LXC containers don't need a full locale stack)
  i18n.defaultLocale = "en_US.UTF-8";

  # SSH — key-only, root login allowed so deploy-rs can push configs
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin         = "prohibit-password";
      PasswordAuthentication  = false;
    };
    # Stable host keys survive nixos-rebuild; sops-nix uses the ed25519 key as
    # the per-host age key for decrypting secrets.
    hostKeys = [
      { type = "ed25519"; path = "/etc/ssh/ssh_host_ed25519_key"; }
      { type = "rsa";     bits = 4096; path = "/etc/ssh/ssh_host_rsa_key"; }
    ];
  };

  users.users.root.openssh.authorizedKeys.keys = sshAuthorizedKeys;

  # sops-nix — derive the age decryption key from this host's SSH host key.
  # After first Terraform provision, get the age pubkey with:
  #   ssh-keyscan -t ed25519 <HOST_IP> | ssh-to-age
  # then add it to nix/secrets/.sops.yaml and re-encrypt.
  sops.age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];

  # Tailscale — auth key comes from a per-host sops secret.
  # Set sops.secrets.tailscale-auth-key in each host that needs it,
  # or keep services.tailscale.authKeyFile pointed at the secret path.
  services.tailscale.enable = true;

  # Firewall — allow SSH and Tailscale by default; each host opens its own ports
  networking.firewall = {
    enable               = true;
    trustedInterfaces    = [ "tailscale0" ];
    allowedTCPPorts      = [ 22 ];
    checkReversePath     = "loose"; # required for Tailscale
  };

  # Minimal tooling available on every host
  environment.systemPackages = with pkgs; [
    curl
    htop
    iproute2
    vim
  ];

  # Auto-upgrade — each host pulls the flake from GitHub and rebuilds itself.
  # This is the homelab equivalent of "deploy-rs as a service": push to the
  # main branch and every host picks it up within the next upgrade window.
  #
  # deploy-rs is still useful for immediate one-off deploys from a dev machine;
  # autoUpgrade handles the steady-state GitOps loop without any extra infra.
  #
  # Hosts upgrade independently with a randomised delay so they don't all
  # restart services at the same time. allowReboot = false keeps services up
  # across kernel upgrades; reboot manually when convenient.
  system.autoUpgrade = {
    enable          = true;
    # github: fetcher resolves the default branch; ?dir=nix points at flake.nix
    flake           = "github:drewnorman/homelab?dir=nix#${flakeAttr}";
    flags           = [ "--accept-flake-config" ];
    dates           = "04:00";
    randomizedDelaySec = 3600;
    allowReboot     = false;
  };

  system.stateVersion = "25.05";
}
