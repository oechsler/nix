{ config, lib, features, ... }:

let
  cfg = config.idle;
  isKde = features.desktop.wm == "kde";
in
{
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

  # KDE — configure PowerDevil via plasma-manager
  config.programs.plasma.powerdevil = lib.mkIf isKde {
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
