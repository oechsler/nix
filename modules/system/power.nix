# Power Management Configuration
#
# This module configures power management behavior:
# - Power Profiles Daemon - Dynamic power profile switching (performance/balanced/power-saver)
# - Power button handling - Delegated to desktop environment
#
# Power button behavior:
# - System (logind): Ignores power button press
# - Desktop: Handles power button via Rofi power menu (Hyprland) or KDE settings
#
# Why ignore logind handling:
# - Desktop environments provide better UX (confirmation dialogs, logout options)
# - Prevents accidental shutdowns from brief button presses

{ ... }:

{
  services.power-profiles-daemon.enable = true;

  # Power button handled by Hyprland/Rofi
  services.logind.settings.Login.HandlePowerKey = "ignore";
}
