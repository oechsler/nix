{ ... }:

{
  services.power-profiles-daemon.enable = true;

  # Power button handled by Hyprland/Rofi
  services.logind.settings.Login.HandlePowerKey = "ignore";
}
