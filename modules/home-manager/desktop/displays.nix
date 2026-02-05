{ config, lib, pkgs, features, displays, ... }:

let
  isKde = features.desktop.wm == "kde";

  kdeTransform = rot: {
    "normal" = "Normal";
    "90"     = "Rotated90";
    "180"    = "Rotated180";
    "270"    = "Rotated270";
  }.${rot};

  kwinOutputConfig = builtins.toJSON [{
    name = "";
    data = map (m: {
      connectorName = m.name;
      enabled = true;
      mode = {
        size = { width = m.width; height = m.height; };
        refreshRate = m.refreshRate * 1000;
      };
      position = { x = m.x; y = m.y; };
      scale = m.scale;
      transform = kdeTransform m.rotation;
    }) displays.monitors;
  }];
in
{
  config = lib.mkIf (isKde && displays.monitors != []) {
    xdg.configFile."kwinoutputconfig.json".text = kwinOutputConfig;
  };
}
