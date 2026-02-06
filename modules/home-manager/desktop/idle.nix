{ config, lib, features, ... }:

let
  cfg = config.idle;
  isKde = features.desktop.wm == "kde";
  ts = toString;
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

  # KDE — write PowerDevil config as a mutable copy (not a read-only symlink)
  # so that KDE can still modify it at runtime.  Overwritten on each rebuild.
  config.home.activation.powerdevilrc = lib.mkIf isKde (
    lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      rm -f "${config.xdg.configHome}/powerdevilrc"
      cat > "${config.xdg.configHome}/powerdevilrc" <<'EOF'
      [AC][Display]
      DimDisplayIdleTimeoutSec=${ts cfg.timeouts.dimAcLockBattery}
      TurnOffDisplayIdleTimeoutSec=${ts cfg.timeouts.lockSuspendAc}

      [AC][SuspendAndShutdown]
      AutoSuspendAction=1
      AutoSuspendIdleTimeoutSec=${ts cfg.timeouts.lockSuspendAc}

      [Battery][Display]
      DimDisplayIdleTimeoutSec=${ts cfg.timeouts.dimBattery}
      TurnOffDisplayIdleTimeoutSec=${ts cfg.timeouts.dimAcLockBattery}

      [Battery][SuspendAndShutdown]
      AutoSuspendAction=1
      AutoSuspendIdleTimeoutSec=${ts cfg.timeouts.suspendBattery}

      [LowBattery][Display]
      DimDisplayIdleTimeoutSec=${ts (cfg.timeouts.dimBattery / 2)}
      TurnOffDisplayIdleTimeoutSec=${ts cfg.timeouts.dimBattery}

      [LowBattery][SuspendAndShutdown]
      AutoSuspendAction=1
      AutoSuspendIdleTimeoutSec=${ts (cfg.timeouts.suspendBattery / 2)}
      EOF
    ''
  );
}
