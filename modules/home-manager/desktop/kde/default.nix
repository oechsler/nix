# KDE Plasma Desktop Modules
#
# This module imports all KDE Plasma-specific configuration:
# - theme.nix - Plasma theming, window decorations, taskbar
# - autostart.nix - XDG .desktop file generation
# - powerdevil.nix - PowerDevil power profiles
# - dolphin.nix - File manager sidebar configuration
# - kscreen.nix - Monitor configuration via kscreen-doctor

{ ... }:

{
  imports = [
    ./theme.nix
    ./autostart.nix
    ./powerdevil.nix
    ./kscreen.nix
    ./dolphin.nix
  ];
}
