# KDE Plasma Desktop Modules
#
# This module imports all KDE Plasma-specific configuration:
# - theme.nix - Plasma theming, window decorations, taskbar
# - autostart.nix - XDG .desktop file generation
# - idle.nix - PowerDevil power profiles
# - dolphin.nix - File manager sidebar configuration
# - displays.nix - Monitor configuration via kscreen-doctor

{ features, lib, ... }:

{
  imports = [
    ./theme.nix
    ./autostart.nix
    ./idle.nix
    ./displays.nix
  ]
  ++ lib.optionals (features.desktop.fileManager == "default") [
    ./dolphin.nix
  ];
}
