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
  config,
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
  inherit (pkgs) vesktop;
  wrapChromiumApp =
    package: binary:
    chromium.wrapHdrSdrApp {
      inherit package binary;
      enable = hasHDR;
    };
  vesktopApp = wrapChromiumApp vesktop "vesktop";
  fluxerDesktopIconSource = pkgs.fetchurl {
    url = "https://raw.githubusercontent.com/fluxerapp/fluxer/1c6fe76185654e2e2fba938479504fd2809111e5/fluxer_desktop/packaging/linux/app.fluxer.Fluxer.svg";
    hash = "sha256-tX0O1rK1SwlT7Obb8AxQ+oMLkd87u5UP2cLNEj/KAJA=";
  };
  fluxerDesktopIcon = pkgs.runCommand "fluxer-desktop-icon.svg" { } ''
    ${pkgs.gnused}/bin/sed \
      's|<g transform="translate(-32.28 -138.64)">|<g transform="translate(2.3709 2.3709) scale(0.86) translate(-32.28 -138.64)">|' \
      ${fluxerDesktopIconSource} > "$out"
  '';
  fluxerCatppuccinSource = pkgs.fetchFromGitHub {
    owner = "scarcekoi";
    repo = "fluxer";
    rev = "4cf7643acd45b7e2ea2a75eafa23d571cb2d457e";
    hash = "sha256-Lhb945NPoV8RK++Dc2P9JY6sTeYE8DF4I5de5jANsng=";
  };
  fluxerCatppuccinCss = "${fluxerCatppuccinSource}/themes/${theme.catppuccin.flavor}/${theme.catppuccin.flavor}-${theme.catppuccin.accent}.css";
  fluxerThemeDirectory = "${config.home.homeDirectory}/.var/app/app.fluxer.Fluxer/data/fluxer-themes";
  fluxerCatppuccinFilename = "catppuccin-${theme.catppuccin.flavor}-${theme.catppuccin.accent}.css";

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
              vesktopApp
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
          package = vesktopApp;
        };

        # Vesktop updates this file at runtime. Remove an old Home Manager
        # symlink once, but preserve any user-managed settings file.
        home.activation.removeManagedVesktopSettings = lib.hm.dag.entryBefore [ "checkLinkTargets" ] ''
          settings_file="${config.xdg.configHome}/vesktop/settings/settings.json"
          if [ -L "$settings_file" ]; then
            ${pkgs.coreutils}/bin/rm -f "$settings_file"
          fi
        '';

        xdg.desktopEntries.vesktop = {
          name = "Discord";
          exec = "${vesktopApp}/bin/vesktop %U";
          icon = "discord";
          categories = [
            "Network"
            "InstantMessaging"
            "Chat"
          ];
          genericName = "Internet Messenger";
        };

        # hypr-dock groups windows by app ID; Obsidian reports md.Obsidian.
        xdg.dataFile = {
          "applications/md.Obsidian.desktop".text = ''
            [Desktop Entry]
            Type=Application
            Name=Obsidian
            Comment=Knowledge base
            Exec=obsidian %u
            Icon=obsidian
            StartupWMClass=md.Obsidian
            NoDisplay=true
          '';
        }
        // lib.optionalAttrs (features.apps.enable && features.flatpak.enable) {
          # Scale Fluxer's pinned upstream SVG slightly smaller than its canvas.
          "applications/app.fluxer.Fluxer.desktop".text = ''
            [Desktop Entry]
            Name=Fluxer
            GenericName=Instant Messenger
            Comment=Instant messaging and VoIP
            Exec=${pkgs.flatpak}/bin/flatpak run app.fluxer.Fluxer %U
            TryExec=${pkgs.flatpak}/bin/flatpak
            Icon=${fluxerDesktopIcon}
            Type=Application
            Categories=Network;InstantMessaging;Chat;
            Keywords=chat;im;messaging;messenger;voip;voice;video;call;
            StartupWMClass=app.fluxer.Fluxer
            SingleMainWindow=true
            StartupNotify=true
            MimeType=x-scheme-handler/fluxer;
            Terminal=false
            X-GNOME-UsesNotifications=true
            Actions=open-settings;new-dm;

            [Desktop Action open-settings]
            Name=Open Settings
            Exec=${pkgs.flatpak}/bin/flatpak run app.fluxer.Fluxer --fluxer-task=open-settings %U

            [Desktop Action new-dm]
            Name=New Direct Message
            Exec=${pkgs.flatpak}/bin/flatpak run app.fluxer.Fluxer --fluxer-task=new-dm %U
          '';
          "applications/ai.storyteller.photocraft.desktop".text = ''
            [Desktop Entry]
            Type=Application
            Name=PhotoCraft
            GenericName=Image Editor
            Comment=Edit photos and layered PSD documents
            Exec=${pkgs.flatpak}/bin/flatpak run --file-forwarding ai.storyteller.photocraft @@ %F @@
            TryExec=${pkgs.flatpak}/bin/flatpak
            Icon=photoshop
            Terminal=false
            StartupNotify=false
            StartupWMClass=ai.storyteller.photocraft
            Categories=Graphics;2DGraphics;RasterGraphics;Photography;
            Keywords=photo;image;editor;psd;layers;retouch;paint;
            MimeType=application/x-photocraft;image/x-paintnet;image/openraster;application/x-krita;image/vnd.adobe.photoshop;image/x-psd;image/x-psb;image/png;image/jpeg;image/tiff;image/webp;image/gif;image/bmp;image/x-tga;image/x-icon;image/vnd.microsoft.icon;image/x-portable-anymap;image/x-portable-bitmap;image/x-portable-graymap;image/x-portable-pixmap;image/x-exr;image/vnd.radiance;image/avif;image/qoi;
          '';
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

      (lib.mkIf features.flatpak.enable {
        # Fluxer imports watched theme folders into its own theme library.
        home.activation.installFluxerCatppuccinTheme = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          theme_directory="${fluxerThemeDirectory}"
          theme_file="$theme_directory/${fluxerCatppuccinFilename}"
          temporary_file="$theme_file.tmp"

          ${pkgs.coreutils}/bin/install -d -m 0755 "$theme_directory"
          ${pkgs.coreutils}/bin/install -m 0644 "${fluxerCatppuccinCss}" "$temporary_file"
          ${pkgs.coreutils}/bin/mv -f "$temporary_file" "$theme_file"
          ${pkgs.coreutils}/bin/install -m 0644 "${fluxerCatppuccinSource}/LICENSE" "$theme_directory/catppuccin-fluxer.LICENSE"
        '';
      })

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
