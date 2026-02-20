# Desktop Environment Modules
#
# This module imports system-level desktop configuration:
# - sddm.nix - SDDM display manager (login screen)
# - hyprland.nix - Hyprland system packages and services
# - kde.nix - KDE Plasma system packages and services
#
# User-level desktop config is in home-manager/desktop/

{ ... }:

{
  imports = [
    ./sddm.nix
    ./hyprland.nix
    ./kde.nix
  ];
}
