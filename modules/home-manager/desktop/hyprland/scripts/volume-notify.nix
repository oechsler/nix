# Volume Notification Script
#
# Shows current volume level and mute status via dunst notification.
# Used as keybinding handler for volume media keys in Hyprland.
{ pkgs }:
pkgs.writeShellScript "volume-notify" ''
  volume=$(${pkgs.wireplumber}/bin/wpctl get-volume @DEFAULT_AUDIO_SINK@ | ${pkgs.gawk}/bin/awk '{printf "%.0f", $2 * 100}')
  muted=$(${pkgs.wireplumber}/bin/wpctl get-volume @DEFAULT_AUDIO_SINK@ | ${pkgs.gnugrep}/bin/grep -c MUTED)

  if [ "$muted" -eq 1 ]; then
    icon="󰝟"
    text="$icon  Stummgeschaltet"
    volume=0
  elif [ "$volume" -ge 70 ]; then
    icon="󰕾"
    text="$icon  Lautstärke ''${volume}%"
  elif [ "$volume" -ge 30 ]; then
    icon="󰖀"
    text="$icon  Lautstärke ''${volume}%"
  else
    icon="󰕿"
    text="$icon  Lautstärke ''${volume}%"
  fi

  ${pkgs.dunst}/bin/dunstify -a "changeVolume" -u low \
    -h string:x-dunst-stack-tag:volume \
    -h int:value:"$volume" \
    "$text"
''
