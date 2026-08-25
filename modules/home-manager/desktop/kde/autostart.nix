# KDE Autostart Configuration
#
# This module generates XDG autostart .desktop entries for KDE.
#
# How it works:
# - Reads autostart.apps list from common/autostart.nix
# - Generates one .desktop file per app in ~/.config/autostart/
# - Plasma exposes these files to its session startup, usually through
#   systemd-xdg-autostart-generator
#
# Hyprland handles the same shared app list differently:
# - hyprland/default.nix generates one systemd user service per app

{ config, lib, ... }:

let
  cfg = config.autostart;

  # Convert app name to desktop file slug
  # Example: "My App" → "my-app"
  slug = app: builtins.replaceStrings [ " " ] [ "-" ] (lib.toLower app.name);
in
{
  #===========================
  # Configuration
  #===========================

  config = {
    # Keep KDE's app startup declarative and let Plasma manage the lifecycle.
    xdg.configFile = builtins.listToAttrs (
      map (app: {
        name = "autostart/${slug app}.desktop";
        value.text = ''
          [Desktop Entry]
          Type=Application
          Name=${app.name}
          Exec=${app.exec}
        '';
      }) cfg.apps
    );
  };
}
