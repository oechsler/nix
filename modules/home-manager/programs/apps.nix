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
#   (Proton Pass uses kernel keyring via keyutils instead)
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
  mumbleDefaults = pkgs.writeText "mumble-settings.json" (
    builtins.toJSON {
      audio = {
        echo_cancel_mode = "Disabled";
        input_system = "PulseAudio";
        output_system = "PulseAudio";
        play_mute_cue = false;
      };
      misc = {
        audio_wizard_has_been_shown = true;
        viewed_server_ping_consent_message = true;
      };
      network.auto_connect_to_last_server = true;
      ui = {
        channel_expansion_mode = "AllChannels";
        disable_public_server_list = true;
        quit_behavior = "AlwaysMinimize";
        send_usage_statistics = false;
        theme = "";
        theme_style = "";
      };
    }
  );
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

          activation.mumbleDefaults = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
            mumble_config="$HOME/.config/Mumble/Mumble/mumble_settings.json"
            if [ ! -e "$mumble_config" ]; then
              mkdir -p "$(dirname "$mumble_config")"
              cp ${mumbleDefaults} "$mumble_config"
            fi
          '';

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
      (lib.mkIf (!isKde) {
        services.gnome-keyring = {
          enable = true;
          components = [ "secrets" ];
        };

        home.packages = with pkgs; [
          baobab
          loupe
          libsecret
        ];
      })
    ]
  );
}
