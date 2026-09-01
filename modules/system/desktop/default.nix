# System Desktop Modules
#
# Imports the system-level pieces shared by, or specific to, the selected
# desktop session. Each child module guards its own configuration with the
# corresponding desktop feature flag.
#
# User-level configuration lives in home-manager/desktop/.

{ config, lib, ... }:

let
  primaryUser = config.users.users.${config.user.name};
in

{
  imports = [
    ./sddm.nix
    ./hyprland.nix
    ./kde.nix
  ];

  # Make nixpkgs Electron/Chromium wrappers prefer native Wayland in graphical
  # sessions. XWayland tends to behave worse with SDR surfaces on HDR desktops.
  environment.sessionVariables.NIXOS_OZONE_WL = lib.mkIf config.features.desktop.enable "1";

  # UDisks mounts removable media below /run/media/<user>. Keep that standard
  # mountpoint for portals and expose a convenient stable alias below /mnt.
  systemd.tmpfiles.rules = lib.mkIf config.features.desktop.enable [
    "d /run/media/${config.user.name} 0700 ${primaryUser.name} ${primaryUser.group} -"
    "L+ /mnt/removable - - - - /run/media/${config.user.name}"
  ];
}
