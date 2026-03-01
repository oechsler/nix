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
# - GNOME Keyring - Secret storage for browsers, VSCode, etc.
# - libsecret - Tools for accessing gnome-keyring (used by Chrome, VSCode, etc.)

{ pkgs, pkgs-stable, features, lib, ... }:

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
      vesktop
      pkgs-stable.freecad      # Pinned to stable: broken on unstable (Boost 1.89)
      pkgs-stable.libreoffice  # Pinned to stable: unstable creates broken noto-fonts-subset derivation
      nextcloud-client
      obsidian
      pika-backup
      prusa-slicer
      spotify
    ] ++ lib.optional features.apps.winboat.enable winboat;
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
    # Used by: Chrome/Chromium, VSCode, Vesktop, etc.
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
      libsecret  # Provides secret-tool and library for apps to access gnome-keyring
    ];
  })
  ]);
}
