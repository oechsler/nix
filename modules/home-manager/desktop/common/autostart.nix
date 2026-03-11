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
# - JetBrains Toolbox (if features.development.enable)
# - Trayscale - Tailscale tray (if features.tailscale.enable)
# - Steam (if features.gaming.enable)
#
# Configuration:
#   autostart.apps = [ { name = "App"; exec = "command"; } ];

{ config, lib, features, ... }:

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

  config = {

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
        { name = "Nheko"; exec = "nheko --tray"; }
        { name = "Mumble"; exec = "mumble --hidden"; }
      ]
      ++ lib.optionals features.development.enable [
        { name = "JetBrains Toolbox"; exec = "jetbrains-toolbox --minimize"; }
      ]
      ++ lib.optionals features.tailscale.enable [
        { name = "Trayscale"; exec = "bash -c 'sleep 3 && trayscale --hide-window'"; }
      ]
      ++ lib.optionals features.gaming.enable [
        { name = "Steam"; exec = "steam -silent"; }
      ];

  };
}
