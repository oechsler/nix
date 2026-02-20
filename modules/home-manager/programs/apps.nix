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
# - Bitwarden - Password manager
# - Vesktop - Discord client
# - Spotify - Music streaming
# - Nextcloud - Cloud sync
# - Obsidian - Note taking
# - LibreOffice - Office suite
# - FreeCAD - 3D CAD
# - PrusaSlicer - 3D printing
# - Pika Backup - Backups
# - Alsa Scarlett GUI - Audio interface control
# - WinBoat - Windows apps in VM with seamless integration
#
# KDE apps:
# - Filelight - Disk usage analyzer
#
# Hyprland apps:
# - Baobab - Disk usage analyzer (GNOME)
# - Loupe - Image viewer (GNOME)
# - GNOME Keyring - Secret storage

{ pkgs, features, lib, ... }:

let
  isKde = features.desktop.wm == "kde";
in
{
  #===========================
  # Configuration
  #===========================

  config = lib.mkIf features.apps.enable (lib.mkMerge [

    #---------------------------
    # Common Apps (All DEs)
    #---------------------------
  {
    home.packages = with pkgs; [
      alsa-scarlett-gui
      bitwarden-desktop
      vesktop
      freecad
      libreoffice
      nextcloud-client
      obsidian
      pika-backup
      prusa-slicer
      spotify
      winboat
    ];
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
    services.gnome-keyring = {
      enable = true;
      components = [ "secrets" ];
    };

    home.packages = with pkgs; [
      baobab
      loupe
    ];
  })
  ]);
}
