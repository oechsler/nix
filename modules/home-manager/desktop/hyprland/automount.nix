# Hyprland removable media automount
#
# Udiskie handles removable media for the standalone Hyprland session. KDE
# uses Plasma's own removable-device settings and does not import this module.

{
  _ ? null,
  ...
}:

{
  # Let udiskie own automounting instead of racing GVFS for the same device.
  dconf.settings."org/gnome/desktop/media-handling" = {
    automount = false;
    automount-open = false;
  };

  services.udiskie = {
    enable = true;
    automount = true;
    notify = true;
    tray = "never";
  };
}
