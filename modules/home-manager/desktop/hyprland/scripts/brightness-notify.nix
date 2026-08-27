# Brightness Notification Script
#
# Shows current brightness level via dunst notification.
# Used as keybinding handler for brightness media keys in Hyprland.
{
  pkgs,
  i18n,
  theme,
}:
let
  icon = "${theme.icons.package}/share/icons/Papirus/32x32/apps/brightness.svg";
in
pkgs.writeShellScript "brightness-notify" ''
  brightness="$1"

  ${pkgs.libnotify}/bin/notify-send -a "changeBrightness" -u low \
    -i "${icon}" \
    -h string:x-dunst-stack-tag:brightness \
    -h string:x-canonical-private-synchronous:brightness \
    -h int:value:"$brightness" \
    "${i18n.translate "Brightness" "Helligkeit"} ''${brightness}%"
''
