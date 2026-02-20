# NixOS Flake Configuration
#
# This flake defines the complete NixOS system configuration.
#
# Structure:
# - inputs: External dependencies (nixpkgs, home-manager, etc.)
# - outputs: NixOS configurations and disko configurations
#
# Hosts:
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
# - cachyos-kernel: Optimized Linux kernel
#
# Usage:
#   nixos-rebuild switch --flake .#samuels-pc
#   nixos-rebuild switch --flake .#samuels-razer
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

  outputs = { self, nixpkgs, ... }@inputs:
    let
      system = "x86_64-linux";

      mkHost = hostName: nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = { inherit inputs; };
        modules = [
          ./hosts/${hostName}/configuration.nix
          inputs.home-manager.nixosModules.default
          inputs.catppuccin.nixosModules.catppuccin
          inputs.sops-nix.nixosModules.sops
          inputs.nix-flatpak.nixosModules.nix-flatpak
          inputs.disko.nixosModules.disko
          inputs.impermanence.nixosModules.impermanence
          {
            nixpkgs.overlays = [
              inputs.cachyos-kernel.overlays.pinned
              (final: prev: {
                hypr-dock = final.callPackage ./packages/hypr-dock.nix { };
              })
            ];
          }
        ];
      };
      pkgs = import nixpkgs { inherit system; };
    in
    {
      diskoConfigurations = {
        samuels-pc = import ./hosts/samuels-pc/disko.nix;
        samuels-razer = import ./hosts/samuels-razer/disko.nix;
      };

      nixosConfigurations = {
        samuels-razer = mkHost "samuels-razer";
        samuels-pc = mkHost "samuels-pc";
      };

      #===========================
      # CI/CD Checks
      #===========================
      checks.${system} = {
        # Custom convention linter (self-documenting)
        # Enforces: NIX_CODE_STYLE.md, NIX_DOCS_STYLE.md
        lint = import ./lint.nix { inherit pkgs; lib = pkgs.lib; };

        # statix: Anti-patterns and best practices (informational)
        # https://github.com/oppiliappan/statix
        # Note: Does not fail build, only reports suggestions
        statix = pkgs.runCommand "statix-check" { } ''
          ${pkgs.statix}/bin/statix check ${./.} \
            --ignore=hosts/*/hardware-configuration.generated.nix \
            --format=stderr \
            2>&1 | tee $out || true
          # Don't fail build on warnings - statix is informational
        '';

        # deadnix: Dead code detection (informational)
        # https://github.com/astro/deadnix
        # Note: Does not fail build, only reports suggestions
        deadnix = pkgs.runCommand "deadnix-check" { } ''
          ${pkgs.deadnix}/bin/deadnix ${./.} 2>&1 | tee $out || true
          # Don't fail build on warnings - deadnix is informational
        '';
      };
    };
}
