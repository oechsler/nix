{ config, lib, pkgs, features, displays, ... }:

let
  isKde = features.desktop.wm == "kde";

  kscreenRotation = rot: {
    "normal" = "normal";
    "90"     = "right";
    "180"    = "inverted";
    "270"    = "left";
  }.${rot};

  monitorArgs = lib.concatMapStringsSep " " (m:
    lib.concatStringsSep " " [
      "output.${m.name}.scale.${toString m.scale}"
      "output.${m.name}.mode.${toString m.width}x${toString m.height}@${toString m.refreshRate}"
      "output.${m.name}.position.${toString m.x},${toString m.y}"
      "output.${m.name}.rotation.${kscreenRotation m.rotation}"
    ]
  ) displays.monitors;

  kscreenDoctor = "${pkgs.kdePackages.libkscreen}/bin/kscreen-doctor";
in
{
  config = lib.mkIf (isKde && displays.monitors != []) {
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
