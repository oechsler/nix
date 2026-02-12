{ config, pkgs, features, lib, ... }:

let
  isKde = features.desktop.wm == "kde";
in
lib.mkIf features.apps.enable (lib.mkMerge [
  # ── Common (all DEs) ──────────────────────────────────────────────────────
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
    ];
  }

  # ── KDE — KDE-native utilities ────────────────────────────────────────────
  (lib.mkIf isKde {
    home.packages = with pkgs; [
      kdePackages.filelight
    ];
  })

  # ── Tiling WMs (Hyprland etc.) — GNOME/GTK utilities ──────────────────────
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
])
