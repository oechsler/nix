# Idle Timeout Configuration (Common)
#
# This module defines idle timeout options used by both Hyprland and KDE.
#
# WM-specific implementation:
# - Hyprland: See hyprland/hypridle.nix (battery-aware idle management)
# - KDE: See kde/idle.nix (PowerDevil power profiles)
#
# Timeout options:
#   idle.timeouts.dimBattery = 120;        # Dim screen on battery (default: 120s = 2min)
#   idle.timeouts.dimAcLockBattery = 300;  # Dim on AC / Lock on battery (default: 300s = 5min)
#   idle.timeouts.suspendBattery = 300;    # Suspend on battery (default: 300s = 5min)
#   idle.timeouts.lockSuspendAc = 1800;    # Lock + suspend on AC (default: 1800s = 30min)

{ lib, ... }:
{
  #===========================
  # Options
  #===========================

  options.idle = {
    timeouts = {
      dimBattery = lib.mkOption {
        type = lib.types.int;
        default = 120;
        description = "Seconds until screen dims on battery";
      };
      dimAcLockBattery = lib.mkOption {
        type = lib.types.int;
        default = 300;
        description = "Seconds until screen dims on AC / locks on battery";
      };
      suspendBattery = lib.mkOption {
        type = lib.types.int;
        default = 300;
        description = "Seconds until suspend on battery";
      };
      lockSuspendAc = lib.mkOption {
        type = lib.types.int;
        default = 1800;
        description = "Seconds until lock + suspend on AC";
      };
    };
  };

}
