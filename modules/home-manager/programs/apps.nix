# Desktop Applications Configuration
#
# This module installs desktop applications when features.apps.enable = true.
# Nextcloud can be disabled independently with features.apps.nextcloud.enable.
#
# Applications are organized by desktop environment:
# - Common (all DEs): Core apps used everywhere
# - KDE: KDE-native utilities
# - Hyprland: GNOME/GTK utilities
#
# Common apps:
# - Mumble - Voice chat (low-latency)
# - Vesktop - Discord client
# - Spotify - Music streaming
# - Nextcloud - Cloud sync
# - Obsidian - Note taking
# - LibreOffice - Office suite
# - FreeCAD - 3D CAD
# - PrusaSlicer - 3D printing
# - Pika Backup - Backups
# - Alsa Scarlett GUI - Audio interface control
#
# Note: Proton Pass is configured in proton-pass.nix
#
# KDE apps:
# - Filelight - Disk usage analyzer
# - KWalletManager - KDE Wallet management
#
# Hyprland apps:
# - Baobab - Disk usage analyzer (GNOME)
# - Loupe - Image viewer (GNOME)
# - GNOME Keyring - Secret storage for browsers, desktop apps, etc.
# - Seahorse - GNOME Keyring management
#   (Proton Pass uses kernel keyring via keyutils instead)
# - libsecret - Tools for accessing gnome-keyring (used by Chrome, Vesktop, etc.)

{
  pkgs,
  features,
  displays,
  lib,
  inputs,
  theme,
  ...
}:

let
  displayHelpers = import ../../lib/displays.nix { inherit lib; };
  hasHDR = displayHelpers.hasDesktopHDR displays.monitors || displays.defaults.hdr == 2;
  isKde = features.desktop.wm == "kde";
  chromium = import ../../lib/chromium.nix { inherit pkgs; };
  wrapChromiumApp =
    package: binary:
    chromium.wrapHdrSdrApp {
      inherit package binary;
      enable = hasHDR;
    };

in
{
  #===========================
  # Configuration
  #===========================

  config = lib.mkIf features.apps.enable (
    lib.mkMerge [

      #---------------------------
      # Common Apps (All DEs)
      #---------------------------
      {
        home = {
          packages =
            with pkgs;
            [
              alsa-scarlett-gui
              (wrapChromiumApp vesktop "vesktop")
              freecad
              libreoffice
            ]
            ++ lib.optionals features.apps.nextcloud.enable [ nextcloud-client ]
            ++ [
              (wrapChromiumApp obsidian "obsidian")
              pika-backup
              prusa-slicer
            ];

        };

        programs.vesktop = {
          enable = true;
          package = null;
          settings = {
            minimizeToTray = true;
            autoStartMinimized = true;
            tray = true;
            clickTrayToShowHide = true;
            arRPC = true;
          };
        };

        xdg.desktopEntries.vesktop = {
          name = "Discord";
          exec = "vesktop %U";
          icon = "discord";
          categories = [
            "Network"
            "InstantMessaging"
            "Chat"
          ];
          genericName = "Internet Messenger";
        };

        programs.spicetify =
          let
            spicePkgs = inputs.spicetify-nix.legacyPackages.${pkgs.stdenv.hostPlatform.system};
          in
          {
            enable = true;
            theme = spicePkgs.themes.catppuccin;
            colorScheme = theme.catppuccin.flavor;
            spotifyLaunchFlags = lib.optionalString hasHDR "--use-gl=egl";
          };
      }

      #---------------------------
      # KDE Apps
      #---------------------------
      (lib.mkIf isKde {
        home.packages = with pkgs; [
          kdePackages.filelight
          kdePackages.kwalletmanager
        ];
      })

      #---------------------------
      # Hyprland Apps
      #---------------------------
      (lib.mkIf (!isKde) {
        home.packages = with pkgs; [
          baobab
          loupe
          libsecret
          seahorse
        ];
      })
    ]
  );
}
