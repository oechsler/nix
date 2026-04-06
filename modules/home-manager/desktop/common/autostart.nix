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

{ config, lib, pkgs, features, ... }:

let
  cfg = config.autostart;
  isKde = features.desktop.wm == "kde";
in
{
  #===========================
  # Options
  #===========================

  options.autostart.apps = lib.mkOption {
    type = lib.types.listOf (lib.types.submodule {
      options = {
        name = lib.mkOption { type = lib.types.str; description = "Human-readable application name"; };
        exec = lib.mkOption { type = lib.types.str; description = "Command to execute"; };
      };
    });
    default = [];
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
      # Core apps (always started)
      [
        { name = "Proton Pass"; exec = "proton-pass --hidden --ozone-platform=wayland"; }
        { name = "Vesktop"; exec = "vesktop --start-minimized"; }
        { name = "CoolerControl"; exec = "coolercontrol"; }
      ]
      # Nextcloud manages its own XDG autostart under KDE; Hyprland needs exec-once
      ++ lib.optionals (!isKde) [
        { name = "Nextcloud"; exec = "nextcloud --background"; }
      ]
      ++ lib.optionals features.apps.enable [
        { name = "Pika Backup Monitor"; exec = "pika-backup-monitor"; }
        { name = "Nheko"; exec = "nheko"; }
        { name = "Mumble"; exec = "mumble --hidden"; }
      ]
      # Trayscale is handled via systemd user service below (reliable tray detection)
      ++ lib.optionals features.gaming.enable [
        { name = "Steam"; exec = "steam -silent"; }
      ];

  }

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
