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
#   - packages.installerIso: Graphical offline installer with all host closures
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
#   See lib.mkHost documentation in docs/QUICKSTART.md
{
  description = "Samuel's NixOS configuration";

  inputs = {
    #===========================
    # Core
    #===========================
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    # Pinned nixpkgs for the CachyOS kernel — bump together with cachyos-kernel
    # when upgrading the kernel version.
    nixpkgs-kernel.url = "github:nixos/nixpkgs/5cca3a89405eb65d2adb43754c2af8dac7b6f2e1";

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
      # Current: rev c69c33c2 (2026-08-20); kernel version tracked by the input
      # MT7927 (WiFi/BT on samuels-terra) requires kernel 7.2+ — bump when available.
      url = "github:xddxdd/nix-cachyos-kernel/c69c33c24148defbcc34ab25456cc460bc33fdbb";
      inputs.nixpkgs.follows = "nixpkgs-kernel";
    };

    # MT7927/MT6639 WiFi 7 Bluetooth support (driver patches + firmware).
    mt7927.url = "github:cmspam/mt7927-nixos";

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
      # Single source of truth for user.name and standalone Disko mounts.
      primaryUser = "samuel";
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
            inherit primaryUser;
          };
          modules = [
            (import ./modules)
            inputs.home-manager.nixosModules.default
            inputs.catppuccin.nixosModules.catppuccin
            inputs.sops-nix.nixosModules.sops
            inputs.disko.nixosModules.disko
            inputs.impermanence.nixosModules.impermanence
            inputs.mt7927.nixosModules.default
            (
              { pkgs, ... }:
              {
                # The patched driver requests the MT6639 blob under mt7927/.
                hardware.firmware = [
                  (pkgs.runCommand "mt7927-firmware-path" { } ''
                    install -d $out/lib/firmware/mediatek/mt7927
                    cp ${
                      inputs.mt7927.packages.${pkgs.stdenv.hostPlatform.system}.firmware
                    }/lib/firmware/mediatek/mt6639/BT_RAM_CODE_MT6639_2_1_hdr.bin \
                      $out/lib/firmware/mediatek/mt7927/
                  '')
                ];
              }
            )

            # Shared overlays (always included)
            inputs.nix-flatpak.nixosModules.nix-flatpak
            {
              nixpkgs.overlays = [
                inputs.cachyos-kernel.overlays.pinned
                (_final: prev: {
                  coreutils-full = prev.uutils-coreutils-noprefix;
                  pam-lldap = prev.callPackage ./modules/packages/pam-lldap.nix { };
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
      mkDisko =
        hostName:
        import ./hosts/${hostName}/disko.nix {
          username = primaryUser;
          inherit lib;
          config = nixosConfigurations.${hostName}.config;
        };

      # Exported mkDisko for external use
      mkDiskoExternal = hostPath: import (hostPath + "/disko.nix");

      pkgs = import nixpkgs { inherit system; };

      #===========================
      # Host Inventory and Closures
      #===========================
      # Every directory with a configuration.nix is a supported host. Keeping
      # this derived from the filesystem prevents the ISO and host outputs from
      # drifting apart when a host is added or removed.
      hostNames = lib.attrNames (
        lib.filterAttrs (
          name: type: type == "directory" && builtins.pathExists ./hosts/${name}/configuration.nix
        ) (builtins.readDir ./hosts)
      );

      nixosConfigurations = lib.genAttrs hostNames mkHost;
      diskoConfigurations = lib.genAttrs hostNames mkDisko;

      # Complete system closures embedded into the offline installer ISO.
      hostClosures = lib.mapAttrs (
        _: host:
        let
          installHost = host.extendModules {
            modules =
              lib.optionals
                (
                  host.config.features.secureBoot.enable || host.config.features.encryption.unlockMethod != "password"
                )
                [
                  {
                    features.secureBoot.enable = lib.mkForce false;
                    features.encryption.unlockMethod = lib.mkForce "password";
                  }
                ];
          };
        in
        installHost.config.system.build.toplevel
      ) nixosConfigurations;
      hostManifest = lib.mapAttrs (
        hostName: host:
        let
          cfg = host.config;
        in
        {
          system = toString hostClosures.${hostName};
          encryption = cfg.features.encryption.enable;
          unlockMethod = cfg.features.encryption.unlockMethod;
          impermanence = cfg.features.impermanence.enable;
          persistPrefix = cfg.features.impermanence.persistPrefix;
          totp = cfg.features.auth.totp.enable;
          yubikey = cfg.features.auth.yubikey.enable;
          yubikeyLuks = cfg.features.encryption.unlockMethod == "yubikey";
          secureBoot = cfg.features.secureBoot.enable;
          desktop = cfg.features.desktop.enable;
          wm = cfg.features.desktop.wm;
          formFactor = cfg.features.hardware.formFactor;
          kernel = cfg.features.kernel;
          kernelVersion = cfg.boot.kernelPackages.kernel.name;
          keyboard = cfg.locale.keyboard;
          language = cfg.locale.language;
          userName = cfg.user.name;
          passwordLocked =
            cfg.user.hashedPassword == "!"
            && !(cfg.sops.secrets ? "user/password")
            && !cfg.features.auth.ldap.enable;
          luksDevices = builtins.attrValues (
            builtins.mapAttrs (_name: dev: dev.device) cfg.boot.initrd.luks.devices
          );
        }
      ) nixosConfigurations;

      #===========================
      # Graphical Offline Installer
      #===========================
      # The ISO is built on a capable machine and contains every host closure.
      # The live installer selects a host from the generated manifest and uses
      # its closure directly, so the target machine does not compile locally.
      mkInstallerIso =
        selectedHosts:
        let
          selectedClosures = lib.getAttrs selectedHosts hostClosures;
          selectedManifest = lib.getAttrs selectedHosts hostManifest;
        in
        (lib.nixosSystem {
          inherit system;
          modules = [
            "${nixpkgs}/nixos/modules/installer/cd-dvd/installation-cd-graphical-base.nix"
            ./modules/installer/iso.nix
            {
              _module.args = {
                diskoPackage = inputs.disko.packages.${system}.disko;
                hostClosures = selectedClosures;
                hostManifest = selectedManifest;
              };
            }
          ];
        }).config.system.build.isoImage;

      installerIso = mkInstallerIso hostNames;
    in
    {
      #===========================
      # Local Host Configurations
      #===========================
      inherit nixosConfigurations diskoConfigurations;

      #===========================
      # Exported Library Functions
      #===========================
      lib = {
        mkHost = mkHostExternal;
        mkDisko = mkDiskoExternal;
      };

      overlays = {
        default = final: _prev: {
          hypr-dock = final.callPackage ./modules/packages/hypr-dock.nix { };
          pam-lldap = final.callPackage ./modules/packages/pam-lldap.nix { };
        };
      };

      # Packages and build artifacts. The installer output is intentionally
      # named separately from regular packages because it is a bootable image.
      packages.${system} = {
        inherit installerIso;
        pam-lldap = pkgs.callPackage ./modules/packages/pam-lldap.nix { };
      };

      #===========================
      # Formatter
      #===========================
      formatter.${system} = pkgs.nixfmt-tree;

      #===========================
      # CI/CD Checks
      #===========================
      checks.${system} = import ./lint.nix { inherit pkgs; };
    };
}
