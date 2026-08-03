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
# Timeouts (from config.idle.*):
# - dimBattery: Dim screen on battery
# - suspendBattery: Lock + suspend on battery
# - dimAc: Dim screen on AC
# - suspendAc: Lock + suspend on AC
#
# Configuration options:
#   hypridle.dim.percent = 30;         # Target brightness percentage when dimmed (default: 30%)
#   hypridle.dim.stepPercent = 5;      # Brightness step size for smooth dim (default: 5%)
#   hypridle.dim.stepDelay = "0.1";    # Delay between steps (default: 0.05s)
#
# Battery detection:
# - Desktop without battery → always treated as AC
# - Laptop with battery → checks /sys/class/power_supply/*/online

{
  config,
  pkgs,
  lib,
  features,
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

  brightnessController = import ./scripts/brightness-controller.nix { inherit pkgs; };
  dimDisplay = "${brightnessController} dim ${toString config.hypridle.dim.percent} ${toString config.hypridle.dim.stepPercent} ${config.hypridle.dim.stepDelay}";
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
  suspendBattery = toString (
    pkgs.writeShellScript "suspend-battery" ''
      ${onBattery} && loginctl lock-session && systemctl suspend
    ''
  );

  # Lock + suspend on AC
  suspendAc = toString (
    pkgs.writeShellScript "suspend-ac" ''
      ${onAC} && loginctl lock-session && systemctl suspend
    ''
  );

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

  options.hypridle.dim = {
    percent = lib.mkOption {
      type = lib.types.ints.between 1 100;
      default = 30;
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
          after_sleep_cmd = "${pkgs.runtimeShell} -c 'for i in 1 2 3; do hyprctl dispatch dpms on 2>/dev/null && break; sleep 0.5; done'";
        };

        listener = sharedListeners ++ lib.optionals isLaptop laptopListeners;
      };
    };
  };
}
