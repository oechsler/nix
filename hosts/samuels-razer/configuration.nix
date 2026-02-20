# samuels-razer Host Configuration
#
# Razer Blade gaming laptop configuration.
#
# Hardware:
# - 14" QHD+ display (3200x1800 @ 60Hz, 1.6x scaling)
# - eDP-1 internal display
#
# Features:
# - KDE Plasma desktop (better for laptop/battery management)
# - Gaming disabled (not primary gaming machine)
# - Smaller terminal font (10pt for high DPI screen)
#
# Differences from samuels-pc:
# - Single internal display vs dual external
# - KDE instead of Hyprland
# - No gaming support
# - Default idle timeouts (shorter, battery-aware)

{ ... }:

{
  imports = [
    ./disko.nix
    ./hardware-configuration.nix
    ./luks.nix

    ../../modules
  ];

  networking.hostName = "samuels-razer";

  #===========================
  # Host-specific Overrides
  #===========================
  displays.monitors = [
    {
      name = "eDP-1";
      width = 3200;
      height = 1800;
      refreshRate = 60;
      scale = 1.6;
      workspaces = [
        1
        2
        3
        4
      ];
    }
  ];

  features.desktop.wm = "kde";
  fonts.defaults.terminalSize = 10;

  features.gaming.enable = false;

  system.stateVersion = "25.11";
}
