{ config, pkgs, ... }:

let
  # Prüft ob eine Batterie existiert und ob wir auf Batterie laufen
  # Ohne Batterie (Desktop) → gilt als AC
  hasBattery = "(test -d /sys/class/power_supply/BAT0 || test -d /sys/class/power_supply/BAT1)";
  acOnline = "(cat /sys/class/power_supply/*/online 2>/dev/null | grep -q 1)";
  onBattery = "${hasBattery} && ! ${acOnline}";
  onAC = "! ${hasBattery} || ${acOnline}";

  dimPercent = 10;
  dimStepPercent = 5;
  dimStepDelay = "0.05";

  # Smooth Dimmen: schrittweise von aktuellem Wert auf Ziel
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
  services.hypridle = {
    enable = true;

    settings = {
      general = {
        lock_cmd = "pidof hyprlock || hyprlock";
        before_sleep_cmd = "loginctl lock-session";
        after_sleep_cmd = "hyprctl dispatch dpms on";
      };

      listener = [
        # 2 Min: Dimmen auf Batterie
        {
          timeout = 120;
          on-timeout = dimBattery;
          on-resume = undim;
        }

        # 5 Min: Dimmen auf Netzteil, Lock auf Batterie
        {
          timeout = 300;
          on-timeout = dimAcLockBattery;
          on-resume = undim;
        }

        # 5 Min: Suspend auf Batterie
        {
          timeout = 300;
          on-timeout = suspendBattery;
        }

        # 30 Min: Lock + Suspend auf Netzteil
        {
          timeout = 1800;
          on-timeout = lockSuspendAC;
        }
      ];
    };
  };
}
