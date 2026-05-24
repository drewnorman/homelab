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

      # SSH public key injected into all hosts. Must match terraform ssh_public_key.
      sshAuthorizedKeys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAA... drew@laptop" # replace with real key
      ];

      # Build a NixOS configuration for a named host.
      mkHost = name: extraModules:
        lib.nixosSystem {
          inherit system;
          specialArgs = {
            inherit sshAuthorizedKeys;
            hostMeta = hosts.${name};
            allHosts = hosts;
          };
          modules = [
            sops-nix.nixosModules.sops
            ./modules/common.nix
            ./hosts/${name}
          ] ++ extraModules;
        };

      # Build a deploy-rs node for a named host.
      mkNode = name: {
        hostname = hosts.${name}.ip;
        profiles.system = {
          sshUser    = "root";
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

      # deploy-rs schema checks — run with `nix flake check`
      checks = builtins.mapAttrs
        (_system: deployLib: deployLib.deployChecks self.deploy)
        deploy-rs.lib;
    };
}
