# Display Configuration
#
# This module defines monitor configuration options.
# Used by: Hyprland, SDDM, and other display managers.
#
# Configuration example:
#   displays.defaultWorkspaceCount = 4;
#   displays.monitors = [
#     {
#       name = "DP-1";
#       width = 2560;
#       height = 1440;
#       refreshRate = 144;
#       x = 0;
#       y = 0;
#       scale = 1.0;
#       vrr = true;                   # VRR/FreeSync — Hyprland: misc.vrr, KDE: vrrpolicy.always
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
              type = lib.types.bool;
              default = false;
              description = "Enable Variable Refresh Rate (VRR/FreeSync/G-Sync) for this monitor";
            };
          };
        }
      );
      default = [ ];
      description = "Per-monitor display configuration";
    };
  };
}
