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
#
# Machine-type behavior (derived from features.hardware.formFactor):
# - Desktop: Lid switch ignore, AMD GPU runpm disabled
# - Laptop:  Lid switch suspend on battery, GPU runpm enabled

{
  config,
  lib,
  ...
}:

let
  cfg = config.features.hardware;
  isLaptop = cfg.formFactor == "laptop";
  hasAmdGpu = cfg.gpu == "amd";
in
{
  services.power-profiles-daemon.enable = true;

  services.logind.settings.Login = {
    InhibitDelayMaxSec = "2s";
    # PowerDevil inhibits this while a KDE session is active. At SDDM there is
    # no inhibitor, so the power button still suspends at the login screen.
    HandlePowerKey = "suspend";
    HandlePowerKeyLongPress = "poweroff";
    HandleSuspendKey = "suspend";
    HandleHibernateKey = "suspend";
    HandleLidSwitch = if isLaptop then "suspend" else "ignore";
    HandleLidSwitchExternalPower = if isLaptop then "suspend" else "ignore";
    HandleLidSwitchDocked = if isLaptop then "suspend" else "ignore";
  };

  systemd.sleep.settings.Sleep = {
    SuspendState = [ "mem" ];
    HibernateDelaySec = "360min";
    AllowSuspend = true;
    AllowHibernation = false;
    AllowSuspendThenHibernate = false;
  };

  # amdgpu.runpm=0 disables GPU runtime PM.
  # On desktop/server: prevents BACO transition issues during suspend (prevents resume hangs).
  # On laptop: runtime PM must stay enabled to allow the GPU to power down on battery.
  boot.kernelParams = lib.optionals (hasAmdGpu && !isLaptop) [
    "amdgpu.runpm=0"
  ];
}
