{
  description = "homelab NixOS configurations — multi-host, managed with deploy-rs";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";

    deploy-rs = {
      url = "github:serokell/deploy-rs";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, deploy-rs, sops-nix, ... }:
    let
      system = "x86_64-linux";
      lib    = nixpkgs.lib;
      hosts  = import ./lib/hosts.nix;

      overlays = [ (import ./overlays/caddy-cloudflare.nix) ];

      # nixpkgs with homelab overlays applied — used for package outputs and
      # threaded into all NixOS configurations via nixpkgs.overlays.
      pkgs = import nixpkgs { inherit system overlays; };

      # SSH public key injected into all hosts. Must match terraform ssh_public_key.
      sshAuthorizedKeys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBty1Aq+Be79tfzubhT7B+jlcZ1xWfWLIszbItuWveAf drew@x1c-g9"
      ];

      # Build a NixOS configuration for a named host.
      mkHost = name: extraModules:
        lib.nixosSystem {
          inherit system;
          specialArgs = {
            inherit sshAuthorizedKeys;
            hostMeta  = hosts.${name};
            allHosts  = hosts;
            flakeAttr = name; # nixosConfigurations key — used by system.autoUpgrade
          };
          modules = [
            { nixpkgs.overlays = overlays; }
            sops-nix.nixosModules.sops
            ./modules/common.nix
            ./hosts/${name}
          ] ++ extraModules;
        };

      # Build a deploy-rs node for a named host.
      mkNode = name: {
        hostname = hosts.${name}.ip;
        profiles.system = {
          sshUser       = "root";
          magicRollback = true;
          path = deploy-rs.lib.${system}.activate.nixos self.nixosConfigurations.${name};
        };
      };

    in {
      nixosConfigurations = {
        adguard     = mkHost "adguard"     [];
        edge        = mkHost "edge"        [];
        homepage    = mkHost "homepage"    [];
        authelia    = mkHost "authelia"    [];
        lldap       = mkHost "lldap"       [];
        jellyfin    = mkHost "jellyfin"    [];
        arr         = mkHost "arr"         [];
        qbittorrent = mkHost "qbittorrent" [];
      };

      deploy.nodes = {
        adguard     = mkNode "adguard";
        edge        = mkNode "edge";
        homepage    = mkNode "homepage";
        authelia    = mkNode "authelia";
        lldap       = mkNode "lldap";
        jellyfin    = mkNode "jellyfin";
        arr         = mkNode "arr";
        qbittorrent = mkNode "qbittorrent";
      };

      # Expose the patched Caddy for easy testing: nix build .#packages.x86_64-linux.caddy-cloudflare
      packages.${system}.caddy-cloudflare = pkgs.caddy-cloudflare;

      # deploy-rs schema checks — run with `nix flake check`
      checks = builtins.mapAttrs
        (_system: deployLib: deployLib.deployChecks self.deploy)
        deploy-rs.lib;
    };
}
