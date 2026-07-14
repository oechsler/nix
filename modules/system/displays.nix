# Display Configuration
#
# This module defines monitor configuration options.
# Used by: Hyprland, SDDM, and other display managers.
#
# Configuration example:
#   displays.defaultWorkspaceCount = 4;
#   displays.defaults.vrr = 1;        # Default for hotplugged/unlisted monitors where supported
#   displays.defaults.hdr = true;     # Default for hotplugged/unlisted monitors where supported
#   displays.monitors = [
#     {
#       name = "DP-1";
#       width = 2560;
#       height = 1440;
#       refreshRate = 144;
#       x = 0;
#       y = 0;
#       scale = 1.0;
#       vrr = 1;                      # VRR/FreeSync: 0=off, 1=always, 2=fullscreen/automatic
#       hdr = true;                   # HDR-capable display — Steam Gamescope HDR flags
#       hdrSdrMaxLuminance = 450;     # SDR white level in nits for HDR output conversion
#       workspaces = [ 1 2 3 4 5 ];  # Hyprland only: bind workspaces to this monitor
#     }
#   ];

{ lib, config, ... }:

{
  #===========================
  # Options
  #===========================

  options.displays = {
    defaultWorkspaceCount = lib.mkOption {
      type = lib.types.int;
      default = 4;
      description = "Default number of workspaces for monitors without an explicit workspace list";
    };

    defaults = {
      vrr = lib.mkOption {
        type = lib.types.enum [
          0
          1
          2
        ];
        default = 1;
        description = "Default Variable Refresh Rate mode for hotplugged/unlisted monitors where the compositor can apply output-independent defaults: 0=off, 1=always, 2=fullscreen/automatic";
      };
      hdr = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Default HDR capability for hotplugged/unlisted monitors where the compositor/session can apply output-independent defaults";
      };
      hdrSdrMaxLuminance = lib.mkOption {
        type = lib.types.ints.between 100 1000;
        default = 450;
        description = "Default SDR white level in nits for HDR output conversion on hotplugged/unlisted monitors where supported";
      };
    };

    monitors = lib.mkOption {
      type = lib.types.listOf (
        lib.types.submodule {
          options = {
            name = lib.mkOption {
              type = lib.types.str;
              description = "Connector name (e.g. DP-1, HDMI-A-1, eDP-1)";
            };
            edidHash = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
              description = "Optional SHA-256 hash of this monitor's EDID for exact SDDM layout matching";
            };
            make = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
              description = "Optional display manufacturer as reported by the compositor";
            };
            model = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
              description = "Optional display model as reported by the compositor";
            };
            serial = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
              description = "Optional display serial number as reported by the compositor";
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
              type = lib.types.enum [
                "normal"
                "90"
                "180"
                "270"
              ];
              default = "normal";
              description = "Display rotation";
            };
            wallpaper = lib.mkOption {
              type = lib.types.nullOr lib.types.path;
              default = null;
              description = "Per-monitor wallpaper (null = use theme.wallpaper)";
            };
            workspaces = lib.mkOption {
              type = lib.types.listOf lib.types.int;
              default = [ ];
              description = "Workspace IDs to bind to this monitor (Hyprland only, e.g. [1 2 3 4 5])";
            };
            vrr = lib.mkOption {
              type = lib.types.enum [
                0
                1
                2
              ];
              default = 0;
              description = "Variable Refresh Rate mode: 0=off, 1=always, 2=fullscreen/automatic";
            };
            hdr = lib.mkOption {
              type = lib.types.bool;
              default = false;
              description = "Mark this monitor as HDR-capable for Steam Gamescope sessions";
            };
            hdrSdrMaxLuminance = lib.mkOption {
              type = lib.types.ints.between 100 1000;
              default = 450;
              description = "SDR white level in nits for HDR output conversion";
            };
          };
        }
      );
      default = [ ];
      description = "Per-monitor display configuration";
    };
  };
}
