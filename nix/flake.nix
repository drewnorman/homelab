{
  description = "homelab NixOS configuration managed with deploy-rs";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
    # Jellyfin LDAP auth currently hangs on newer 10.11 builds; pin to 10.11.2.
    nixpkgs-jellyfin.url = "github:NixOS/nixpkgs/a563ddee940a08599b5401e5415479fcd5a1ce7f";

    deploy-rs = {
      url = "github:serokell/deploy-rs";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixos-generators = {
      url = "github:nix-community/nixos-generators";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    impermanence.url = "github:nix-community/impermanence";
  };

  outputs = { self, nixpkgs, nixpkgs-jellyfin, deploy-rs, sops-nix, nixos-generators, impermanence, ... }:
    let
      system = "x86_64-linux";
      lib    = nixpkgs.lib;
      pkgs   = import nixpkgs { inherit system; };
      pkgsJellyfin = import nixpkgs-jellyfin { inherit system; };
      hosts  = import ./lib/hosts.nix;

      coreHosts = [
        "core"
      ];

      # SSH public key injected into lab-core. Must match terraform ssh_public_key.
      sshAuthorizedKeys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBty1Aq+Be79tfzubhT7B+jlcZ1xWfWLIszbItuWveAf drew@x1c-g9"
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGqQo/lOhSqVSWgM0aFAu1gZ5tKnKpCDISg5dHDD0B5Y drew@nix.lab.adre.me"
      ];

      mkVmHost = name: extraModules:
        lib.nixosSystem {
          inherit system;
          specialArgs = {
            inherit sshAuthorizedKeys;
            inherit pkgsJellyfin;
            hostMeta  = hosts.${name};
            flakeAttr = name;
          };
          modules = [
            sops-nix.nixosModules.sops
            ./modules/vm-common.nix
            ./modules/lldap-provision.nix
            ./hosts/${name}
          ] ++ extraModules;
        };

      # Build a deploy-rs node for a named host.
      mkNode = name: sshHost: {
        hostname = sshHost;
        profiles.system = {
          sshUser       = "root";
          magicRollback = true;
          path = deploy-rs.lib.${system}.activate.nixos self.nixosConfigurations.${name};
        };
      };

    in {
      nixosConfigurations = {
        core = mkVmHost "core" [];
      };

      deploy.nodes = {
        core = mkNode "core" hosts.core.sshHost;
        core-tailscale = mkNode "core" hosts.core.tailscaleSshHost;
      };

      packages.${system} = {
        proxmox-template = nixos-generators.nixosGenerate {
          inherit system;
          format = "proxmox";
          modules = [
            ./images/proxmox-template.nix
          ];
        };

        # Pin deploy-rs to the flake-locked version: nix run .#deploy-rs -- --help
        deploy-rs = deploy-rs.packages.${system}.deploy-rs;

        deploy-core = pkgs.writeShellApplication {
          name = "deploy-core";
          runtimeInputs = [ deploy-rs.packages.${system}.deploy-rs ];
          text = lib.concatMapStringsSep "\n" (host: "deploy \"$@\" .#${host}") coreHosts;
        };

        deploy-core-tailscale = pkgs.writeShellApplication {
          name = "deploy-core-tailscale";
          runtimeInputs = [ deploy-rs.packages.${system}.deploy-rs ];
          text = "deploy \"$@\" .#core-tailscale";
        };
      };

      apps.${system} = {
        deploy-core = {
          type = "app";
          program = "${self.packages.${system}.deploy-core}/bin/deploy-core";
        };

        deploy-core-tailscale = {
          type = "app";
          program = "${self.packages.${system}.deploy-core-tailscale}/bin/deploy-core-tailscale";
        };
      };

      # deploy-rs schema checks — run with `nix flake check`
      checks = builtins.mapAttrs
        (_system: deployLib: deployLib.deployChecks self.deploy)
        deploy-rs.lib;
    };
}
