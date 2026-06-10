# Battery Warning Script
#
# Monitors battery level and shows warnings or auto-suspends.
# Runs as systemd user service, checking every 60 seconds:
# - ≤5%: Critical warning + auto-suspend after 5 seconds.
# - ≤10%: Warning, once per discharge cycle.
# - >10% or charging: Reset warning flag.
{ pkgs }:
pkgs.writeShellScript "battery-warning" ''
  warned=""
  while true; do
    capacity=$(cat /sys/class/power_supply/BAT*/capacity 2>/dev/null | head -1)
    status=$(cat /sys/class/power_supply/BAT*/status 2>/dev/null | head -1)

    if [ -n "$capacity" ] && [ "$status" = "Discharging" ]; then
      if [ "$capacity" -le 5 ]; then
        ${pkgs.dunst}/bin/dunstify -a "battery" -u critical -t 5000 \
          -h string:x-dunst-stack-tag:battery \
          "󰂃  Akku kritisch" "Gerät wird in den Ruhezustand versetzt."
        sleep 5
        systemctl suspend
      elif [ "$capacity" -le 10 ] && [ -z "$warned" ]; then
        ${pkgs.dunst}/bin/dunstify -a "battery" -u critical -t 15000 \
          -h string:x-dunst-stack-tag:battery \
          "󰁺  Niedriger Akkustand (''${capacity}%)" "Bitte Ladegerät anschließen."
        warned="1"
      fi
    fi

    [ "$status" != "Discharging" ] && warned=""
    sleep 60
  done
''
