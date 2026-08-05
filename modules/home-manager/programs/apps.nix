# Desktop Applications Configuration
#
# This module installs desktop applications when features.apps.enable = true.
#
# Applications are organized by desktop environment:
# - Common (all DEs): Core apps used everywhere
# - KDE: KDE-native utilities
# - Hyprland: GNOME/GTK utilities
#
# Common apps:
# - Nheko - Matrix client (native Qt, E2EE)
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
# Optional apps (with feature toggles):
# - WinBoat - Windows VM with seamless integration (features.apps.winboat.enable)
#
# KDE apps:
# - Filelight - Disk usage analyzer
#
# Hyprland apps:
# - Baobab - Disk usage analyzer (GNOME)
# - Loupe - Image viewer (GNOME)
# - GNOME Keyring - Secret storage for browsers, desktop apps, etc.
# - libsecret - Tools for accessing gnome-keyring (used by Chrome, Vesktop, etc.)

{
  pkgs,
  features,
  displays,
  lib,
  fonts,
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
              mumble
              nheko
              (wrapChromiumApp vesktop "vesktop")
              freecad
              libreoffice
              nextcloud-client
              (wrapChromiumApp obsidian "obsidian")
              pika-backup
              prusa-slicer
            ]
            ++ lib.optional features.apps.winboat.enable (wrapChromiumApp winboat "winboat");

          # Mumble theme: don't set explicitly — uses system Qt theme (Catppuccin via Kvantum)

          activation.nhekoTheme = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
            conf="$HOME/.config/nheko/nheko.conf"
            if [ -f "$conf" ]; then
              ${pkgs.gnused}/bin/sed -i \
                -e 's/^theme=.*/theme=dark/' \
                -e 's/^window\\start_in_tray=.*/window\\start_in_tray=true/' \
                -e 's/^window\\tray=.*/window\\tray=true/' \
                -e "s/^font_family=.*/font_family=${fonts.ui}/" \
                -e "s/^font_size=.*/font_size=${toString fonts.size}/" \
                "$conf"
            fi
          '';
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
        ];
      })

      #---------------------------
      # Hyprland Apps
      #---------------------------
      # GNOME/GTK utilities for tiling WMs
      (lib.mkIf (!isKde) {
        # GNOME Keyring for credential storage
        # Used by: Chrome/Chromium, Vesktop, etc.
        # Note: Proton Pass uses kernel keyring instead (via keyutils)
        # Unlock: pam_gnome_keyring captures the SDDM password at login and
        # auto-unlocks the keyring. sddm/polkit/hyprlock are password-only for
        # this reason (YubiKey login skips pam_gnome_keyring's auth phase).
        services.gnome-keyring = {
          enable = true;
          components = [ "secrets" ];
        };

        home.packages = with pkgs; [
          baobab
          loupe
          libsecret # Provides secret-tool and library for apps to access gnome-keyring
        ];
      })
    ]
  );
}
