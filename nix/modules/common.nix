# Shared base configuration for all homelab NixOS LXC containers.
# Each host imports this module; per-service config lives in hosts/<name>/.
{ lib, pkgs, sshAuthorizedKeys, hostMeta, flakeAttr, ... }:
{
  networking.hostName = hostMeta.hostname;

  # Proxmox LXC — no bootloader, no initrd
  boot.isContainer = true;

  # Unprivileged Proxmox LXCs cannot mount kernel debugfs.
  systemd.suppressedSystemUnits = [ "sys-kernel-debug.mount" ];

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
  sops.age.sshKeyPaths = [ "/persist/etc/ssh/ssh_host_ed25519_key" ];

  # Impermanence — /persist is the only durable storage on each host.
  # Everything else is ephemeral and starts clean on container restart.
  # /persist itself lives on the Proxmox LVM root disk.
  system.activationScripts.create-persist.text = "mkdir -p /persist";

  environment.persistence."/persist" = {
    hideMounts = true;
    directories = [
      "/var/lib/tailscale"   # Tailscale node identity + state
    ];
    files = [
      # SSH host keys must survive restarts — sops-nix derives the age
      # decryption key from the ed25519 host key.
      "/etc/ssh/ssh_host_ed25519_key"
      "/etc/ssh/ssh_host_ed25519_key.pub"
      "/etc/ssh/ssh_host_rsa_key"
      "/etc/ssh/ssh_host_rsa_key.pub"
    ];
  };

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

  # Deployment is intentionally push-based: OpenTofu owns Proxmox resources,
  # and deploy-rs/GitHub Actions owns NixOS activation. Keep host self-upgrade
  # disabled so there is one default control loop to debug when a deploy fails.
  system.autoUpgrade = {
    enable = false;
    flake  = "github:drewnorman/homelab?dir=nix#${flakeAttr}";
    flags  = [ "--accept-flake-config" ];
  };

  system.stateVersion = "25.05";
}
