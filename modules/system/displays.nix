{ lib, config, ... }:

{
  options.displays = {
    monitors = lib.mkOption {
      type = lib.types.listOf (lib.types.submodule {
        options = {
          name = lib.mkOption {
            type = lib.types.str;
            description = "Connector name (e.g. DP-1, HDMI-A-1, eDP-1)";
          };
          width = lib.mkOption {
            type = lib.types.int;
            default = 1920;
            description = "Horizontal resolution";
          };
          height = lib.mkOption {
            type = lib.types.int;
            default = 1080;
            description = "Vertical resolution";
          };
          refreshRate = lib.mkOption {
            type = lib.types.int;
            default = 60;
            description = "Refresh rate in Hz";
          };
          x = lib.mkOption {
            type = lib.types.int;
            default = 0;
            description = "Horizontal position offset";
          };
          y = lib.mkOption {
            type = lib.types.int;
            default = 0;
            description = "Vertical position offset";
          };
          scale = lib.mkOption {
            type = lib.types.float;
            default = config.theme.scale;
            description = "Scale factor (defaults to theme.scale)";
          };
          rotation = lib.mkOption {
            type = lib.types.enum [ "normal" "90" "180" "270" ];
            default = "normal";
            description = "Display rotation";
          };
          wallpaper = lib.mkOption {
            type = lib.types.nullOr lib.types.path;
            default = null;
            description = "Per-monitor wallpaper (null = use theme.wallpaper)";
          };
        };
      });
      default = [];
      description = "Per-monitor display configuration";
    };
  };
}
