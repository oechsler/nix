# Power Management Configuration
#
# This module configures power management behavior:
# - Power Profiles Daemon - Dynamic power profile switching (performance/balanced/power-saver)
# - Power button handling - Suspend by default, overridden by desktop environments
#
# Power button behavior:
# - System and Steam Machine session: Suspend immediately like SteamOS
# - Hyprland desktop: Inhibits logind and handles the button via Rofi power menu
# - KDE desktop: Inhibits logind through PowerDevil and uses KDE power settings

_:

{
  services.power-profiles-daemon.enable = true;

  services.logind.settings.Login.HandlePowerKey = "suspend";
}
