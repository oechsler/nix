# Brightness Notification Script
#
# Shows current brightness level via dunst notification.
# Used as keybinding handler for brightness media keys in Hyprland.
{ pkgs }:
pkgs.writeShellScript "brightness-notify" ''
  brightness=$(${pkgs.brightnessctl}/bin/brightnessctl -m | ${pkgs.gawk}/bin/awk -F, '{print substr($4, 0, length($4)-1)}')

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
