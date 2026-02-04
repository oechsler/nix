{ config, pkgs, lib, ... }:

let
  cfg = config.hypridle;
  # Check battery status (desktop without battery counts as AC)
  hasBattery = "(test -d /sys/class/power_supply/BAT0 || test -d /sys/class/power_supply/BAT1)";
  acOnline = "(cat /sys/class/power_supply/*/online 2>/dev/null | grep -q 1)";
  onBattery = "${hasBattery} && ! ${acOnline}";
  onAC = "! ${hasBattery} || ${acOnline}";

  dimPercent = cfg.dim.percent;
  dimStepPercent = cfg.dim.stepPercent;
  dimStepDelay = cfg.dim.stepDelay;

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

  undim = toString (pkgs.writeShellScript "undim" ''
    brightnessctl -r
  '');

  dimBattery = toString (pkgs.writeShellScript "dim-battery" ''
    ${onBattery} && ${smoothDim}
  '');

  dimAcLockBattery = toString (pkgs.writeShellScript "dim-ac-lock-battery" ''
    if ${onBattery}; then
      loginctl lock-session
    else
      ${smoothDim}
    fi
  '');

  suspendBattery = toString (pkgs.writeShellScript "suspend-battery" ''
    ${onBattery} && systemctl suspend
  '');

  lockSuspendAC = toString (pkgs.writeShellScript "lock-suspend-ac" ''
    ${onAC} && loginctl lock-session && systemctl suspend
  '');
in
{
  options.hypridle = {
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
    dim = {
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
  };

  config.services.hypridle = {
    enable = true;

    settings = {
      general = {
        lock_cmd = "pidof hyprlock || hyprlock";
        before_sleep_cmd = "loginctl lock-session";
        after_sleep_cmd = "hyprctl dispatch dpms on";
      };

      listener = [
        # dim on battery
        {
          timeout = cfg.timeouts.dimBattery;
          on-timeout = dimBattery;
          on-resume = undim;
        }

        # dim on AC, lock on battery
        {
          timeout = cfg.timeouts.dimAcLockBattery;
          on-timeout = dimAcLockBattery;
          on-resume = undim;
        }

        # suspend on battery
        {
          timeout = cfg.timeouts.suspendBattery;
          on-timeout = suspendBattery;
        }

        # lock + suspend on AC
        {
          timeout = cfg.timeouts.lockSuspendAc;
          on-timeout = lockSuspendAC;
        }
      ];
    };
  };
}
