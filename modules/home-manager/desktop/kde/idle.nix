# KDE Idle/Power Management Configuration
#
# This module configures KDE PowerDevil power profiles.
#
# Features:
# - Three profiles: AC, Battery, Low Battery
# - Uses timeout values from common/idle.nix
# - Battery-aware behavior (aggressive power saving on battery)
#
# Behavior:
# - AC profile: Dim → Turn off display → Suspend (slow timeouts)
# - Battery profile: Dim (fast) → Turn off display → Suspend (fast)
# - Low battery: Even faster timeouts (half of battery timeouts)
#
# Hyprland uses these same timeouts:
# - See hyprland/hypridle.nix

{ config, lib, ... }:

let
  cfg = config.idle;
in
{
  #===========================
  # Configuration
  #===========================

  config.programs.plasma.powerdevil = {

    #---------------------------
    # AC Profile
    #---------------------------
    # Behavior when plugged in
    AC = {
      dimDisplay = {
        enable = true;
        idleTimeout = cfg.timeouts.dimAcLockBattery;
      };
      turnOffDisplay.idleTimeout = cfg.timeouts.lockSuspendAc;
      autoSuspend = {
        action = "sleep";
        idleTimeout = cfg.timeouts.lockSuspendAc;
      };
    };

    #---------------------------
    # Battery Profile
    #---------------------------
    # Behavior when on battery power
    battery = {
      dimDisplay = {
        enable = true;
        idleTimeout = cfg.timeouts.dimBattery;
      };
      turnOffDisplay.idleTimeout = cfg.timeouts.dimAcLockBattery;
      autoSuspend = {
        action = "sleep";
        idleTimeout = cfg.timeouts.suspendBattery;
      };
    };

    #---------------------------
    # Low Battery Profile
    #---------------------------
    # Aggressive power saving when battery is low
    # Uses half of normal battery timeouts
    lowBattery = {
      dimDisplay = {
        enable = true;
        idleTimeout = cfg.timeouts.dimBattery / 2;
      };
      turnOffDisplay.idleTimeout = cfg.timeouts.dimBattery;
      autoSuspend = {
        action = "sleep";
        idleTimeout = cfg.timeouts.suspendBattery / 2;
      };
    };
  };
}
