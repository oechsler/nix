# Hypridle Configuration (Idle Management)
#
# This module configures hypridle for automatic screen dimming, locking, and suspend.
#
# Key features:
# - Battery-aware behavior (different timings for AC vs battery)
# - Smooth screen dimming (gradual brightness reduction)
# - Automatic lock and suspend
# - Resume actions (restore brightness, turn on screen)
#
# Timeouts (from config.idle.*):
# - idle.dimTimeout: Dim screen (smooth dim on AC, instant on battery)
# - idle.lockTimeout: Lock screen (AC) or suspend (battery)
# - idle.suspendTimeout: Suspend system (battery only)
#
# Configuration options:
#   hypridle.dim.percent = 10;         # Target brightness when dimmed (default: 10%)
#   hypridle.dim.stepPercent = 5;      # Brightness step for smooth dim (default: 5%)
#   hypridle.dim.stepDelay = "0.1";    # Delay between steps (default: 0.1s)
#
# Battery detection:
# - Desktop without battery → always treated as AC
# - Laptop with battery → checks /sys/class/power_supply/*/online

{ config, pkgs, lib, ... }:

let
  inherit (config) idle;

  # ============================================================================
  # BATTERY DETECTION HELPERS
  # ============================================================================
  # Check if system has a battery
  hasBattery = "(test -d /sys/class/power_supply/BAT0 || test -d /sys/class/power_supply/BAT1)";

  # Check if AC adapter is online
  acOnline = "(cat /sys/class/power_supply/*/online 2>/dev/null | grep -q 1)";

  # Battery vs AC conditions
  onBattery = "${hasBattery} && ! ${acOnline}";
  onAC = "! ${hasBattery} || ${acOnline}";

  # Smooth dim configuration
  dimPercent = config.hypridle.dim.percent;
  dimStepPercent = config.hypridle.dim.stepPercent;
  dimStepDelay = config.hypridle.dim.stepDelay;

  # ============================================================================
  # SMOOTH DIM SCRIPT
  # ============================================================================
  # Gradually reduce brightness to target percentage
  #
  # How it works:
  # 1. Save current brightness
  # 2. Calculate target brightness (dimPercent of max)
  # 3. Step down by dimStepPercent every dimStepDelay seconds
  # 4. Stop at target brightness
  smoothDim = toString (pkgs.writeShellScript "smooth-dim" ''
    brightnessctl -s
    current=$(brightnessctl get)
    max=$(brightnessctl max)
    target=$((max * ${toString dimPercent} / 100))
    step=$((max * ${toString dimStepPercent} / 100))
    while [ "$current" -gt "$target" ]; do
      current=$((current - step))
      [ "$current" -lt "$target" ] && current=$target
      brightnessctl set "$current" -q
      sleep ${dimStepDelay}
    done
  '');

  # Restore brightness to saved value
  undim = toString (pkgs.writeShellScript "undim" ''
    brightnessctl -r
  '');

  # Dim screen only on battery (instant dim, no smooth transition)
  dimBattery = toString (pkgs.writeShellScript "dim-battery" ''
    ${onBattery} && ${smoothDim}
  '');

  # Battery-aware lock/dim behavior
  # - On battery: Lock screen immediately
  # - On AC: Smooth dim (warning before lock)
  dimAcLockBattery = toString (pkgs.writeShellScript "dim-ac-lock-battery" ''
    if ${onBattery}; then
      loginctl lock-session
    else
      ${smoothDim}
    fi
  '');

  # Suspend only on battery
  suspendBattery = toString (pkgs.writeShellScript "suspend-battery" ''
    ${onBattery} && systemctl suspend
  '');

  # Lock and suspend on AC (e.g., long idle on desktop)
  lockSuspendAC = toString (pkgs.writeShellScript "lock-suspend-ac" ''
    ${onAC} && loginctl lock-session && systemctl suspend
  '');
in
{
  #===========================
  # Options
  #===========================

  # Smooth dim configuration (Hyprland-specific)
  options.hypridle.dim = {
    percent = lib.mkOption {
      type = lib.types.int;
      default = 10;
      description = "Target brightness percentage when dimmed";
    };
    stepPercent = lib.mkOption {
      type = lib.types.int;
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

  config.services.hypridle = {
    enable = true;

    settings = {
      general = {
        lock_cmd = "pidof hyprlock || hyprlock";
        before_sleep_cmd = "loginctl lock-session && sleep 2";
        after_sleep_cmd = "hyprctl dispatch dpms on";
      };

      listener = [
        # dim on battery
        {
          timeout = idle.timeouts.dimBattery;
          on-timeout = dimBattery;
          on-resume = undim;
        }

        # dim on AC, lock on battery
        {
          timeout = idle.timeouts.dimAcLockBattery;
          on-timeout = dimAcLockBattery;
          on-resume = undim;
        }

        # suspend on battery
        {
          timeout = idle.timeouts.suspendBattery;
          on-timeout = suspendBattery;
        }

        # lock + suspend on AC
        {
          timeout = idle.timeouts.lockSuspendAc;
          on-timeout = lockSuspendAC;
        }
      ];
    };
  };
}
