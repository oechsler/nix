# Autostart Configuration (Common)
#
# This module defines applications that start automatically on login.
#
# Features:
# - Cross-WM support (Hyprland and KDE)
# - Feature-flag aware (only starts apps if features enabled)
#
# WM-specific implementation:
# - Hyprland: Uses exec-once in hyprland/default.nix
# - KDE: See kde/autostart.nix for XDG .desktop generation
#
# Default autostart apps:
# - Proton Pass - Password manager
# - Vesktop - Discord client (minimized)
# - CoolerControl - Fan control
# - Nextcloud - Cloud sync (Hyprland only, KDE uses XDG autostart)
# - Pika Backup Monitor (if features.apps.enable)
# - Nheko - Matrix client (tray, if features.apps.enable)
# - Trayscale - Tailscale tray (if features.tailscale.enable)
# - Steam (if features.gaming.enable)
#
# Configuration:
#   autostart.apps = [ { name = "App"; exec = "command"; } ];

{
  config,
  lib,
  pkgs,
  features,
  ...
}:

let
  cfg = config.autostart;
  isKde = features.desktop.wm == "kde";
in
{
  #===========================
  # Options
  #===========================

  options.autostart.apps = lib.mkOption {
    type = lib.types.listOf (
      lib.types.submodule {
        options = {
          name = lib.mkOption {
            type = lib.types.str;
            description = "Human-readable application name";
          };
          exec = lib.mkOption {
            type = lib.types.str;
            description = "Command to execute";
          };
        };
      }
    );
    default = [ ];
    description = "Applications to start on login (works on both Hyprland and KDE)";
  };

  #===========================
  # Configuration
  #===========================

  config = lib.mkMerge [
    {

      #---------------------------
      # Default Autostart Apps
      #---------------------------
      autostart.apps =
        lib.optionals features.apps.enable [
          {
            name = "Proton Pass";
            exec = "proton-pass --hidden --ozone-platform=wayland";
          }
          {
            name = "Vesktop";
            exec = "vesktop --start-minimized";
          }
          {
            name = "Nheko";
            exec = "nheko";
          }
          {
            name = "Mumble";
            exec = "mumble";
          }
        ]
        # Trayscale/CoolerControl are explicit systemd services (portal ordering, tray detection)
        ++ lib.optionals features.gaming.enable [
          {
            name = "Steam";
            exec = "steam -silent";
          }
        ];

      #---------------------------
      # Nextcloud XDG Autostart (declarative)
      #---------------------------
      # Nextcloud creates ~/.config/autostart/Nextcloud.desktop at runtime — not
      # declarative. We own the file so it exists on fresh installs and the
      # systemd-xdg-autostart-generator picks it up on both Hyprland and KDE.
      # Pika Backup: the package ships its own autostart .desktop, no entry needed.
      xdg.configFile."autostart/Nextcloud.desktop" = lib.mkIf features.apps.enable {
        text = ''
          [Desktop Entry]
          Type=Application
          Name=Nextcloud
          Exec=nextcloud --background
        '';
      };

    }

    #---------------------------
    # CoolerControl systemd service
    # (must start after portal so Tauri/WebKitGTK picks up prefer-dark)
    #---------------------------
    (lib.mkIf (!isKde) {
      systemd.user.services.coolercontrol = {
        Unit = {
          Description = "CoolerControl - Fan control";
          After = [
            "graphical-session.target"
            "xdg-desktop-portal-gtk.service"
          ];
          PartOf = [ "graphical-session.target" ];
        };
        Service = {
          ExecStart = "${pkgs.coolercontrol.coolercontrol-gui}/bin/coolercontrol";
          Restart = "on-failure";
          RestartSec = 3;
          # Exit code 1 = another instance already running (single-instance detection).
          # Don't restart in that case — it's not a real crash.
          RestartPreventExitStatus = 1;
        };
        Install.WantedBy = [ "graphical-session.target" ];
      };
    })

    #---------------------------
    # Trayscale systemd service
    # (reliable: waits for graphical-session.target, restarts on failure)
    #---------------------------
    (lib.mkIf features.tailscale.enable {
      systemd.user.services.trayscale = {
        Unit = {
          Description = "Trayscale - Tailscale tray applet";
          After = [ "graphical-session.target" ];
          PartOf = [ "graphical-session.target" ];
        };
        Service = {
          ExecStart = "${pkgs.trayscale}/bin/trayscale --hide-window";
          Restart = "on-failure";
          RestartSec = 3;
        };
        Install.WantedBy = [ "graphical-session.target" ];
      };
    })

  ]; # end mkMerge
}
