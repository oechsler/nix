# Brightness Notification Script
#
# Shows current brightness level via dunst notification.
# Used as keybinding handler for brightness media keys in Hyprland.
{ pkgs }:
pkgs.writeShellScript "brightness-notify" ''
  if (set -- /sys/class/backlight/*; test -e "$1"); then
    brightness=$(${pkgs.brightnessctl}/bin/brightnessctl -m | ${pkgs.gawk}/bin/awk -F, '{print substr($4, 0, length($4)-1)}')
  elif ${pkgs.ddcutil}/bin/ddcutil detect --terse 2>/dev/null | grep -q .; then
    display=$(${pkgs.ddcutil}/bin/ddcutil detect --terse 2>/dev/null | ${pkgs.gawk}/bin/awk '$1 == "Display" { print $2; exit }')
    values=$(${pkgs.ddcutil}/bin/ddcutil --display "$display" getvcp 10 --terse 2>/dev/null | ${pkgs.gawk}/bin/awk '$1 == "VCP" { print $4, $5; exit }')
    set -- $values
    if [ -n "$1" ]; then
      brightness=$((100 * $1 / $2))
    else
      brightness=100
    fi
  else
    brightness=100
  fi

  if [ "$brightness" -ge 70 ]; then
    icon="󰃠"
  elif [ "$brightness" -ge 30 ]; then
    icon="󰃟"
  else
    icon="󰃞"
  fi

  ${pkgs.dunst}/bin/dunstify -a "changeBrightness" -u low \
    -h string:x-dunst-stack-tag:brightness \
    -h int:value:"$brightness" \
    "$icon  Helligkeit ''${brightness}%"
''
