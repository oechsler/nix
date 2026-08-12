# NixOS Flake Configuration
#
# This flake defines the complete NixOS system configuration.
#
# Structure:
# - inputs: External dependencies (nixpkgs, home-manager, etc.)
# - outputs:
#   - lib.mkHost: Reusable function for building NixOS systems
#   - lib.mkDisko: Helper for importing disko configurations (optional)
#   - nixosConfigurations: Local host configurations (samuels-terra, samuels-razer, etc.)
#   - diskoConfigurations: Disk layouts for local hosts
#   - formatter: nixfmt for `nix fmt`
#   - checks: CI/CD linters (custom conventions, statix, deadnix)
#
# Local Hosts:
# - samuels-razer: Razer Blade Stealth 13 2018 (i7-8550U, Intel UHD 620)
# - samuels-ser9: Beelink SER9 Mini PC (Ryzen AI 9 HX 370, Radeon 890M)
# - samuels-terra: Desktop workstation (2x 1440p, Ryzen 9 9950X3D2, RX 9070 XT)
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
#   nixos-rebuild switch --flake .#samuels-terra
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

    # Pinned nixpkgs for the CachyOS kernel — bump together with cachyos-kernel
    # when upgrading the kernel version.
    nixpkgs-kernel.url = "github:nixos/nixpkgs/5c406c24ab27a146b8321f419a5536e3cf6842a0";

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
    catppuccin = {
      url = "github:catppuccin/nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    spicetify-nix = {
      url = "github:Gerg-L/spicetify-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    #===========================
    # External Packages
    #===========================
    cachyos-kernel = {
      # Pinned: nix flake update must not silently bump the kernel version.
      # Bump this together with nixpkgs-kernel when upgrading the kernel.
      # See: github.com/xddxdd/nix-cachyos-kernel (version.json tracks kernel versions)
      # Current: rev 0a8acbc0 (2026-08-12), kernel null
      # MT7927 (WiFi/BT on samuels-terra) requires kernel 7.2+ — bump when available.
      url = "github:xddxdd/nix-cachyos-kernel/0a8acbc03e3b4eaa05d478d675a8dc4362f03fea";
      inputs.nixpkgs.follows = "nixpkgs-kernel";
    };

    firefox-addons = {
      url = "gitlab:rycee/nur-expressions?dir=pkgs/firefox-addons";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nix-flatpak.url = "github:gmodena/nix-flatpak";

  };

  outputs =
    { nixpkgs, ... }@inputs:
    let
      # All hosts in this flake are x86_64-linux.
      # Adding an aarch64 host would require parameterizing mkHostBase.
      system = "x86_64-linux";
      inherit (nixpkgs) lib;

      # Base host builder with shared configuration
      mkHostBase =
        {
          hostName,
          hostPath,
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
                (_final: prev: {
                  coreutils-full = prev.uutils-coreutils-noprefix;
                })
              ];
            }
          ]
          ++ lib.optionals withHyprDock [
            # Local-only overlay (only for this repo's hosts)
            {
              nixpkgs.overlays = [
                (final: _prev: {
                  hypr-dock = final.callPackage ./modules/packages/hypr-dock.nix { };
                })
              ];
            }
          ]
          ++ [
            {
              networking.hostName = hostName;
              home-manager = {
                useGlobalPkgs = true;
                useUserPackages = true;
                extraSpecialArgs = { };
                sharedModules = [
                  (import ./modules/home-manager)
                  inputs.catppuccin.homeModules.catppuccin
                  inputs.sops-nix.homeManagerModules.sops
                  inputs.plasma-manager.homeModules.plasma-manager
                  inputs.spicetify-nix.homeManagerModules.spicetify
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
          extraModules ? [ ],
        }:
        mkHostBase {
          inherit
            hostName
            hostPath
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
        samuels-ser9 = mkHost "samuels-ser9";
        samuels-terra = mkHost "samuels-terra";
      };

      diskoConfigurations = {
        samuels-razer = mkDisko "samuels-razer";
        samuels-ser9 = mkDisko "samuels-ser9";
        samuels-terra = mkDisko "samuels-terra";
      };

      #===========================
      # Exported Library Functions
      #===========================
      lib = {
        mkHost = mkHostExternal;
        mkDisko = mkDiskoExternal;
      };

      overlays = {
        default = final: _prev: {
          hypr-dock = final.callPackage ./packages/hypr-dock.nix { };
        };
      };

      #===========================
      # Formatter
      #===========================
      formatter.${system} = pkgs.nixfmt-tree;

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
          # Copy source and remove generated hardware configs before checking
          cp -r ${./.} ./source
          chmod -R +w ./source
          rm -f ./source/hosts/*/hardware-configuration.generated.nix
          ${pkgs.statix}/bin/statix check ./source --format=stderr
          touch $out
        '';

        # deadnix: Dead code detection (enforced)
        # https://github.com/astro/deadnix
        deadnix = pkgs.runCommand "deadnix-check" { } ''
          ${pkgs.deadnix}/bin/deadnix ${./.}
          touch $out
        '';

        # shellcheck: Shell script linter (enforced)
        # https://www.shellcheck.net
        shellcheck = pkgs.runCommand "shellcheck-check" { } ''
          ${pkgs.shellcheck}/bin/shellcheck ${./.}/*.sh
          touch $out
        '';

        format = pkgs.runCommand "nixfmt-check" { } ''
          find ${./.} -name '*.nix' ! -name 'hardware-configuration.generated.nix' -print0 \
            | xargs --null --no-run-if-empty ${pkgs.nixfmt}/bin/nixfmt --check
          touch $out
        '';
      };
    };
}
