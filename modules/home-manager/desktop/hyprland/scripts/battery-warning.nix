# Battery Warning Script
#
# Monitors battery level and shows warnings or auto-suspends.
# Runs as systemd user service, checking every 60 seconds:
# - ≤5%: Critical warning + auto-suspend after 5 seconds.
# - ≤10%: Warning, once per discharge cycle.
# - >10% or charging: Reset warning flag.
{
  pkgs,
  i18n,
  theme,
}:
let
  lowBattery = i18n.translate "Low battery" "Niedriger Akkuzustand";
  batteryIcon = "${theme.icons.package}/share/icons/Papirus/32x32/devices/battery.svg";
in
pkgs.writeShellScript "battery-warning" ''
  set -eu

  warned=""
  while true; do
    capacity="$(${pkgs.coreutils}/bin/cat /sys/class/power_supply/BAT*/capacity 2>/dev/null \
      | ${pkgs.coreutils}/bin/head -1 || true)"
    status="$(${pkgs.coreutils}/bin/cat /sys/class/power_supply/BAT*/status 2>/dev/null \
      | ${pkgs.coreutils}/bin/head -1 || true)"

    if [ -n "$capacity" ] && [ "$status" = "Discharging" ]; then
      if [ "$capacity" -le 5 ]; then
        ${pkgs.libnotify}/bin/notify-send -a "battery" -u critical -t 5000 \
          -i "${batteryIcon}" \
          -h string:x-dunst-stack-tag:battery \
          -h string:x-canonical-private-synchronous:battery \
          "${i18n.translate "Critical battery level" "Kritischer Akkuzustand"}" "${i18n.translate "Please connect the charger." "Bitte das Ladegerät anschließen."}"
        ${pkgs.coreutils}/bin/sleep 5
        ${pkgs.systemd}/bin/systemctl suspend
      elif [ "$capacity" -le 10 ] && [ -z "$warned" ]; then
        ${pkgs.libnotify}/bin/notify-send -a "battery" -u critical -t 15000 \
          -i "${batteryIcon}" \
          -h string:x-dunst-stack-tag:battery \
          -h string:x-canonical-private-synchronous:battery \
          "${lowBattery} (''${capacity}%)" "${i18n.translate "Please connect the charger." "Bitte das Ladegerät anschließen."}"
        warned="1"
      fi
    fi

    [ "$status" != "Discharging" ] && warned=""
    ${pkgs.coreutils}/bin/sleep 60
  done
''
