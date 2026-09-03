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

{
  config,
  lib,
  features,
  ...
}:

let
  cfg = config.idle;
  isLaptop = features.hardware.formFactor == "laptop";
  batteryProfile = brightness: {
    powerButtonAction = "showLogoutScreen";
    whenLaptopLidClosed = "sleep";
    inhibitLidActionWhenExternalMonitorConnected = false;
    dimDisplay = {
      enable = true;
      idleTimeout = cfg.timeouts.dimBattery;
    };
    displayBrightness = brightness;
    turnOffDisplay = {
      idleTimeout = cfg.timeouts.suspendBattery;
      idleTimeoutWhenLocked = cfg.timeouts.suspendBattery;
    };
    autoSuspend = {
      action = "sleep";
      idleTimeout = cfg.timeouts.suspendBattery;
    };
  };
in
{
  #===========================
  # Configuration
  #===========================

  config = {
    programs.plasma = {
      powerdevil = {

        #---------------------------
        # AC Profile
        #---------------------------
        # Behavior when plugged in
        AC = {
          powerButtonAction = "showLogoutScreen";
          # Keep the laptop awake while docked, but switch the internal panel
          # off when the lid closes. The external output remains available.
          whenLaptopLidClosed = if isLaptop then "turnOffScreen" else "sleep";
          inhibitLidActionWhenExternalMonitorConnected = !isLaptop;
          dimDisplay = {
            enable = true;
            idleTimeout = cfg.timeouts.dimAc;
          };
          displayBrightness = 100;
          turnOffDisplay = {
            idleTimeout = cfg.timeouts.suspendAc;
            idleTimeoutWhenLocked = cfg.timeouts.suspendAc;
          };
          autoSuspend = {
            action = "sleep";
            idleTimeout = cfg.timeouts.suspendAc;
          };
        };

        # Battery profiles use the same timeouts; only the target brightness differs.
        battery = batteryProfile 70;
        lowBattery = batteryProfile 30;
      };

      # Lock on the AC suspend schedule and require the password immediately.
      kscreenlocker = {
        autoLock = true;
        timeout = cfg.timeouts.suspendAc / 60;
        lockOnResume = true;
        passwordRequired = true;
        passwordRequiredDelay = 0;
      };

      # Keep the current brightness in every profile. The dimming timer remains
      # enabled, but PowerDevil must not use a profile-specific brightness.
      configFile = {
        powerdevilrc = {
          "AC/Display".UseProfileSpecificDisplayBrightness = lib.mkForce false;
          "Battery/Display".UseProfileSpecificDisplayBrightness = lib.mkForce false;
          "LowBattery/Display".UseProfileSpecificDisplayBrightness = lib.mkForce false;
        };
      };
    };
  };
}
