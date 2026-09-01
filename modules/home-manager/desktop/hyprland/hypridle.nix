# Hypridle Configuration (Idle Management)
#
# This module configures hypridle for automatic screen dimming, locking, and suspend.
#
# Key features:
# - Battery-aware behavior (different timings for AC vs battery)
# - Unified brightness control: backlight, DDC/CI, then gamma fallback
# - Automatic lock and suspend
# - Resume actions (restore brightness, turn on screen)
#
# Timeouts (from idle.timeouts.*):
# - dimBattery: Dim screen on battery
# - suspendBattery: Lock + suspend on battery
# - dimAc: Dim screen on AC
# - suspendAc: Lock + suspend on AC
#
# Configuration options:
#   idle.hypridle.dim.percent = 10;         # Target brightness percentage when dimmed (default: 10%)
#   idle.hypridle.dim.stepPercent = 5;      # Brightness step size for smooth dim (default: 5%)
#   idle.hypridle.dim.stepDelay = "0.05";   # Delay between steps (default: 0.05s)
#
# Battery detection:
# - Desktop without battery → always treated as AC
# - Laptop with battery → checks /sys/class/power_supply/*/online

{
  config,
  pkgs,
  lib,
  features,
  i18n,
  theme,
  ...
}:

let
  inherit (config) idle;

  isLaptop = features.hardware.formFactor == "laptop";

  # ============================================================================
  # BATTERY DETECTION HELPERS
  # ============================================================================
  hasBattery = "(test -d /sys/class/power_supply/BAT0 || test -d /sys/class/power_supply/BAT1)";
  acOnline = "(cat /sys/class/power_supply/*/online 2>/dev/null | grep -q 1)";
  onBattery = "${hasBattery} && ! ${acOnline}";
  onAC = "! ${hasBattery} || ${acOnline}";

  brightnessController = import ./scripts/brightness-controller.nix { inherit pkgs i18n theme; };
  lockSuspend = import ./scripts/lock-suspend.nix { inherit pkgs; };
  dimDisplay = "${brightnessController} dim ${toString idle.hypridle.dim.percent} ${toString idle.hypridle.dim.stepPercent} ${idle.hypridle.dim.stepDelay}";
  undimDisplay = "${brightnessController} restore";

  # ============================================================================
  # IDLE ACTION SCRIPTS
  # ============================================================================

  # Dim screen on battery
  dimBattery = toString (
    pkgs.writeShellScript "dim-battery" ''
      ${onBattery} && ${dimDisplay}
    ''
  );

  # Dim screen on AC
  dimAc = toString (
    pkgs.writeShellScript "dim-ac" ''
      ${onAC} && ${dimDisplay}
    ''
  );

  # Lock + suspend on battery
  # Charger transitions can make the battery listener fire while its idle
  # timeout is already elapsed. Require stable battery operation first.
  suspendBattery = "${onBattery} && sleep 10 && ${onBattery} && ${lockSuspend}";

  # Lock + suspend on AC
  suspendAc = "${onAC} && ${lockSuspend}";

  # ============================================================================
  # LISTENERS
  # ============================================================================

  # Shared listeners (both desktop and laptop)
  sharedListeners = [
    {
      timeout = idle.timeouts.dimAc;
      on-timeout = dimAc;
      on-resume = undimDisplay;
    }
    {
      timeout = idle.timeouts.suspendAc;
      on-timeout = suspendAc;
    }
  ];

  # Laptop-only listeners (battery-specific)
  laptopListeners = [
    {
      timeout = idle.timeouts.dimBattery;
      on-timeout = dimBattery;
      on-resume = undimDisplay;
    }
    {
      timeout = idle.timeouts.suspendBattery;
      on-timeout = suspendBattery;
    }
  ];
in
{
  #===========================
  # Options
  #===========================

  options.idle.hypridle.dim = {
    percent = lib.mkOption {
      type = lib.types.ints.between 1 100;
      default = 10;
      description = "Target brightness percentage when dimmed";
    };
    stepPercent = lib.mkOption {
      type = lib.types.ints.between 1 100;
      default = 5;
      description = "Brightness step size for smooth dimming";
    };
    stepDelay = lib.mkOption {
      type = lib.types.str;
      default = "0.05";
      description = "Delay between dim steps in seconds";
    };
  };

  #===========================
  # Configuration
  #===========================

  config = {
    home.packages =
      lib.optionals isLaptop [ pkgs.brightnessctl ] ++ lib.optionals (!isLaptop) [ pkgs.hyprsunset ];

    services.hypridle = {
      enable = true;

      settings = {
        general = {
          lock_cmd = "pidof hyprlock || hyprlock";
          before_sleep_cmd = "loginctl lock-session";
          # Do not restart portals after every resume: this can terminate
          # active PipeWire screen-capture sessions. Hyprland, wallpaper,
          # locker, and display state are refreshed independently.
          after_sleep_cmd = "${pkgs.runtimeShell} -c 'hyprctl reload 2>/dev/null || true; ${brightnessController} restore 2>/dev/null || true; systemctl --user try-restart awww.service 2>/dev/null || true; pkill -USR2 hyprlock 2>/dev/null || true; for i in 1 2 3; do hyprctl dispatch dpms on 2>/dev/null && break; sleep 0.5; done'";
        };

        listener = sharedListeners ++ lib.optionals isLaptop laptopListeners;
      };
    };
  };
}
