{ config, lib, features, ... }:

let
  cfg = config.idle;
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
}
