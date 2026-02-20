# Desktop Environment User Configuration
#
# This module conditionally imports desktop configuration based on WM choice.
#
# Structure:
# - common/ - Shared config (GTK theme, bookmarks, autostart, idle)
# - hyprland/ - Hyprland-specific (waybar, rofi, hyprlock, etc.)
# - kde/ - KDE-specific (Plasma settings, Dolphin, displays)
#
# Only loads when features.desktop.enable = true
# Loads WM-specific modules based on features.desktop.wm

{ features, lib, ... }:

{
  imports = lib.optionals features.desktop.enable (
    [ ./common ]
    ++ lib.optionals (features.desktop.wm == "hyprland") [ ./hyprland ]
    ++ lib.optionals (features.desktop.wm == "kde") [ ./kde ]
  );
}
