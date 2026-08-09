# Desktop Environment Modules
#
# This module imports system-level desktop configuration:
# - sddm.nix - SDDM display manager (login screen)
# - hyprland.nix - Hyprland system packages and services
# - kde.nix - KDE Plasma system packages and services
#
# User-level desktop config is in home-manager/desktop/

{ config, lib, ... }:

{
  imports = [
    ./sddm.nix
    ./hyprland.nix
    ./kde.nix
  ];

  # Make nixpkgs Electron/Chromium wrappers prefer native Wayland in graphical
  # sessions. XWayland tends to behave worse with SDR surfaces on HDR desktops.
  environment.sessionVariables.NIXOS_OZONE_WL = lib.mkIf config.features.desktop.enable "1";
}
