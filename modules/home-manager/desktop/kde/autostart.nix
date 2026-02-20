# KDE Autostart Configuration
#
# This module generates XDG autostart .desktop entries for KDE.
#
# How it works:
# - Reads autostart.apps list from common/autostart.nix
# - Generates .desktop file for each app in ~/.config/autostart/
# - KDE automatically launches these apps on login
#
# Hyprland handles autostart differently:
# - Uses exec-once in hyprland/default.nix

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
    # Generate XDG autostart .desktop entries for KDE
    xdg.configFile = builtins.listToAttrs (map (app: {
      name = "autostart/${slug app}.desktop";
      value.text = ''
        [Desktop Entry]
        Type=Application
        Name=${app.name}
        Exec=${app.exec}
      '';
    }) cfg.apps);
  };
}
