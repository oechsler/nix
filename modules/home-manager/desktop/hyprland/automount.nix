# Hyprland removable media automount
#
# GVFS handles removable media for the standalone Hyprland session. KDE uses
# Plasma's own removable-device settings and does not import this module.

{ ... }:

{
  dconf.settings."org/gnome/desktop/media-handling" = {
    automount = true;
    automount-open = false;
  };
}
