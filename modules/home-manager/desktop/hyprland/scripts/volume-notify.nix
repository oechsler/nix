# Volume Notification Script
#
# Shows current volume level and mute status via dunst notification.
# Used as keybinding handler for volume media keys in Hyprland.
{
  pkgs,
  i18n,
  theme,
}:
let
  iconDir = "${theme.icons.package}/share/icons/Papirus/32x32/status";
in
pkgs.writeShellScript "volume-notify" ''
  volume=$(${pkgs.wireplumber}/bin/wpctl get-volume @DEFAULT_AUDIO_SINK@ | ${pkgs.gawk}/bin/awk '{printf "%.0f", $2 * 100}')
  muted=$(${pkgs.wireplumber}/bin/wpctl get-volume @DEFAULT_AUDIO_SINK@ | ${pkgs.gnugrep}/bin/grep -c MUTED)

  if [ "$muted" -eq 1 ]; then
    icon="${iconDir}/audio-volume-muted.svg"
    text="${i18n.translate "Muted" "Stummgeschaltet"}"
    volume=0
  elif [ "$volume" -ge 70 ]; then
    icon="${iconDir}/audio-volume-high.svg"
    text="${i18n.translate "Volume" "Lautstärke"} ''${volume}%"
  elif [ "$volume" -ge 30 ]; then
    icon="${iconDir}/audio-volume-medium.svg"
    text="${i18n.translate "Volume" "Lautstärke"} ''${volume}%"
  else
    icon="${iconDir}/audio-volume-low.svg"
    text="${i18n.translate "Volume" "Lautstärke"} ''${volume}%"
  fi

  ${pkgs.dunst}/bin/dunstify -a "changeVolume" -u low \
    -i "$icon" \
    -h string:x-dunst-stack-tag:volume \
    -h int:value:"$volume" \
    "$text"
''
