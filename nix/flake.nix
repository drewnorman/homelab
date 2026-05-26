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

    impermanence.url = "github:nix-community/impermanence";
  };

  outputs = { self, nixpkgs, deploy-rs, sops-nix, impermanence, ... }:
    let
      system = "x86_64-linux";
      lib    = nixpkgs.lib;
      pkgs   = import nixpkgs { inherit system; };
      hosts  = import ./lib/hosts.nix;

      coreHosts = [
        "adguard"
        "edge"
        "monitoring"
        "authelia"
        "lldap"
        "jellyfin"
      ];

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
            flakeAttr = name; # nixosConfigurations key for optional host self-upgrade
          };
          modules = [
            sops-nix.nixosModules.sops
            impermanence.nixosModules.impermanence
            ./modules/common.nix
            ./modules/lldap-provision.nix
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
        monitoring  = mkHost "monitoring"  [];
        authelia    = mkHost "authelia"    [];
        lldap       = mkHost "lldap"       [];
        jellyfin    = mkHost "jellyfin"    [];
        arr         = mkHost "arr"         [];
        qbittorrent = mkHost "qbittorrent" [];
      };

      deploy.nodes = {
        adguard     = mkNode "adguard";
        edge        = mkNode "edge";
        monitoring  = mkNode "monitoring";
        authelia    = mkNode "authelia";
        lldap       = mkNode "lldap";
        jellyfin    = mkNode "jellyfin";
        arr         = mkNode "arr";
        qbittorrent = mkNode "qbittorrent";
      };

      packages.${system} = {
        # Pin deploy-rs to the flake-locked version: nix run .#deploy-rs -- --help
        deploy-rs = deploy-rs.packages.${system}.deploy-rs;

        deploy-core = pkgs.writeShellApplication {
          name = "deploy-core";
          runtimeInputs = [ deploy-rs.packages.${system}.deploy-rs ];
          text = lib.concatMapStringsSep "\n" (host: "deploy \"$@\" ${self.outPath}/nix#${host}") coreHosts;
        };
      };

      apps.${system}.deploy-core = {
        type = "app";
        program = "${self.packages.${system}.deploy-core}/bin/deploy-core";
      };

      # deploy-rs schema checks — run with `nix flake check`
      checks = builtins.mapAttrs
        (_system: deployLib: deployLib.deployChecks self.deploy)
        deploy-rs.lib;
    };
}
