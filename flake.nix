# NixOS Flake Configuration
#
# This flake defines the complete NixOS system configuration.
#
# Structure:
# - inputs: External dependencies (nixpkgs, home-manager, etc.)
# - outputs:
#   - lib.mkHost: Reusable function for building NixOS systems
#   - lib.mkDisko: Helper for importing disko configurations (optional)
#   - nixosConfigurations: Local host configurations (samuels-pc, samuels-razer)
#   - diskoConfigurations: Disk layouts for local hosts
#   - checks: CI/CD linters (custom conventions, statix, deadnix)
#
# Local Hosts:
# - samuels-pc: Desktop workstation (2x 1440p, Secure Boot, dual-boot)
# - samuels-razer: Laptop (gaming laptop, portable workstation)
#
# Key inputs:
# - nixpkgs: NixOS packages (unstable channel)
# - home-manager: User-level configuration
# - disko: Declarative disk partitioning
# - impermanence: Root filesystem rollback on reboot
# - lanzaboote: Secure Boot support
# - sops-nix: Encrypted secrets management
# - catppuccin: Catppuccin theming
# - plasma-manager: KDE Plasma declarative config
#
# Custom packages:
# - hypr-dock: Application dock for Hyprland (local package)
# - cachyos-kernel: Optimized Linux kernel (shared with external repos)
#
# Usage (local hosts):
#   nixos-rebuild switch --flake .#samuels-pc
#   nixos-rebuild switch --flake .#samuels-razer
#
# Usage (as dependency in other repos):
#   See lib.mkHost documentation in README.md
{
  description = "Samuel's NixOS configuration";

  inputs = {
    #===========================
    # Core
    #===========================
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    #===========================
    # Nix Community Tools
    #===========================
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    impermanence.url = "github:nix-community/impermanence";

    lanzaboote = {
      url = "github:nix-community/lanzaboote";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    plasma-manager = {
      url = "github:nix-community/plasma-manager";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.home-manager.follows = "home-manager";
    };

    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    #===========================
    # Theming
    #===========================
    catppuccin.url = "github:catppuccin/nix";

    #===========================
    # External Packages
    #===========================
    awww.url = "git+https://codeberg.org/LGFae/awww";

    cachyos-kernel = {
      url = "github:xddxdd/nix-cachyos-kernel";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    firefox-addons = {
      # Pinned: rev d886ec7 (2026-02-19) broke the build — flake.nix passes { fetchurl, lib, stdenv }
      # but default.nix expects buildMozillaXpiAddon. Upstream bug, remove pin when fixed.
      url = "gitlab:rycee/nur-expressions/fb51502bcbd21fc84a1aae6a75564a968e6b0c25?dir=pkgs/firefox-addons";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nix-flatpak.url = "github:gmodena/nix-flatpak";
  };

  outputs =
    { self, nixpkgs, ... }@inputs:
    let
      system = "x86_64-linux";
      inherit (nixpkgs) lib;

      # Base host builder with shared configuration
      mkHostBase =
        {
          hostName,
          hostPath,
          serverMode ? false,
          extraModules ? [ ],
          withHyprDock ? false,
        }:
        lib.nixosSystem {
          inherit system;
          specialArgs = {
            inherit inputs;
            inherit hostPath;
          };
          modules = [
            (import ./modules)
            inputs.home-manager.nixosModules.default
            inputs.catppuccin.nixosModules.catppuccin
            inputs.sops-nix.nixosModules.sops
            inputs.disko.nixosModules.disko
            inputs.impermanence.nixosModules.impermanence

            # Shared overlays (always included)
            inputs.nix-flatpak.nixosModules.nix-flatpak
            {
              nixpkgs.overlays = [
                inputs.cachyos-kernel.overlays.pinned
              ];
            }
          ]
          ++ lib.optionals withHyprDock [
            # Local-only overlay (only for this repo's hosts)
            {
              nixpkgs.overlays = [
                (final: prev: {
                  hypr-dock = final.callPackage ./packages/hypr-dock.nix { };
                })
              ];
            }
          ]
          ++ [
            {
              networking.hostName = hostName;
              features.server = serverMode;

              home-manager = {
                useGlobalPkgs = true;
                useUserPackages = true;
                sharedModules = [
                  (import ./modules/home-manager)
                  inputs.catppuccin.homeManagerModules.catppuccin
                ];
              };
            }
            (hostPath + "/configuration.nix")
          ]
          ++ extraModules;
        };

      # Internal mkHost for this repo's hosts (with hypr-dock overlay)
      mkHost =
        hostName:
        mkHostBase {
          inherit hostName;
          hostPath = ./hosts/${hostName};
          withHyprDock = true;
        };

      # Exported mkHost for use in other repos (without local overlays)
      mkHostExternal =
        {
          hostName,
          hostPath,
          serverMode ? false,
          extraModules ? [ ],
        }:
        mkHostBase {
          inherit
            hostName
            hostPath
            serverMode
            extraModules
            ;
        };

      # Internal mkDisko for this repo's hosts
      mkDisko = hostName: import ./hosts/${hostName}/disko.nix;

      # Exported mkDisko for external use
      mkDiskoExternal = hostPath: import (hostPath + "/disko.nix");

      pkgs = import nixpkgs { inherit system; };
    in
    {
      #===========================
      # Local Host Configurations
      #===========================
      nixosConfigurations = {
        samuels-razer = mkHost "samuels-razer";
        samuels-pc = mkHost "samuels-pc";
      };

      diskoConfigurations = {
        samuels-pc = mkDisko "samuels-pc";
        samuels-razer = mkDisko "samuels-razer";
      };

      #===========================
      # Exported Library Functions
      #===========================
      lib = {
        mkHost = mkHostExternal;
        mkDisko = mkDiskoExternal;
      };

      #===========================
      # CI/CD Checks
      #===========================
      checks.${system} = {
        # Custom convention linter (self-documenting)
        # Enforces: NIX_CODE_STYLE.md, NIX_DOCS_STYLE.md
        lint = import ./lint.nix {
          inherit pkgs;
          inherit (pkgs) lib;
        };

        # statix: Anti-patterns and best practices (enforced)
        # https://github.com/oppiliappan/statix
        statix = pkgs.runCommand "statix-check" { } ''
          ${pkgs.statix}/bin/statix check ${./.} \
            --ignore hosts/samuels-pc/hardware-configuration.generated.nix \
            --ignore hosts/samuels-razer/hardware-configuration.generated.nix \
            --format=stderr
          touch $out
        '';

        # deadnix: Dead code detection (enforced)
        # https://github.com/astro/deadnix
        deadnix = pkgs.runCommand "deadnix-check" { } ''
          ${pkgs.deadnix}/bin/deadnix ${./.}
          touch $out
        '';
      };
    };
}
