# Display Configuration (KDE)
#
# This module applies display configuration for KDE Plasma.
# Hyprland uses displays.monitors directly in hyprland.nix.
#
# Features:
# - Applies display configuration at KDE startup
# - Configures resolution, position, scale, rotation per monitor
# - Uses kscreen-doctor (KDE's display configuration tool)
#
# Configuration consumed from displays.monitors:
# - Resolution: widthxheight@refreshRate
# - Position: x,y coordinates
# - Scale: DPI scaling factor
# - Rotation: normal, 90, 180, 270
# - VRR: vrr = 0/1/2 → vrrpolicy.never/always/automatic
# - HDR: hdr = true → highDynamicRange + wideColorGamut + SDR white level when supported by KScreen
#
# Note: Only active when features.desktop.wm == "kde" and displays.monitors is not empty

{
  lib,
  pkgs,
  features,
  displays,
  ...
}:

let
  isKde = features.desktop.wm == "kde";
  kscreen = import ../../../lib/kscreen.nix { inherit lib; };
  monitorArgs = kscreen.monitorArgs displays.monitors;

  kscreenDoctor = "${pkgs.kdePackages.libkscreen}/bin/kscreen-doctor";
in
{
  #===========================
  # Configuration
  #===========================

  # KDE only: Apply display config at startup
  config = lib.mkIf (isKde && displays.monitors != [ ]) {
    # Generate autostart .desktop entry that runs kscreen-doctor
    xdg.configFile."autostart/nix-display-config.desktop".text = ''
      [Desktop Entry]
      Type=Application
      Name=Apply NixOS Display Configuration
      Exec=${kscreenDoctor} ${monitorArgs}
      X-KDE-autostart-phase=1
      OnlyShowIn=KDE;
    '';
  };
}
