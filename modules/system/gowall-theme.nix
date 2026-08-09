# Gowall Theme + Catppuccinize Options
#
# Generates a gowall-compatible 26-color JSON theme from the Catppuccin palette.
# The theme is always available internally (readOnly). All user-facing toggles
# live under catppuccinize.*.
{
  config,
  pkgs,
  lib,
  ...
}:

let
  flavor = config.catppuccin.flavor;
  accent = config.catppuccin.accent;
  catppuccinPalette = lib.importJSON "${config.catppuccin.sources.palette}/palette.json";
  flavorColors = catppuccinPalette.${flavor}.colors;

  gowallColorOrder = [
    "rosewater"
    "flamingo"
    "pink"
    "mauve"
    "red"
    "maroon"
    "peach"
    "yellow"
    "green"
    "teal"
    "sky"
    "sapphire"
    "blue"
    "lavender"
    "text"
    "subtext1"
    "subtext0"
    "overlay2"
    "overlay1"
    "overlay0"
    "surface2"
    "surface1"
    "surface0"
    "base"
    "mantle"
    "crust"
  ];

  themeName = "catppuccin-${flavor}-${accent}";
  themeColors = map (name: flavorColors.${name}.hex) gowallColorOrder;

  themeJSON = pkgs.writeText "gowall-${themeName}.json" (
    builtins.toJSON {
      name = themeName;
      colors = themeColors;
    }
  );
in
{
  options.catppuccinize = {
    enable =
      lib.mkEnableOption "apply Catppuccin color grading to wallpapers and tray icons via gowall"
      // {
        default = true;
      };

    icons.enable =
      lib.mkEnableOption "use Catppuccin-colored icon theme and gowall-processed tray icons"
      // {
        default = true;
      };

    background.enable = lib.mkEnableOption "apply Catppuccin color grade to wallpapers via gowall" // {
      default = true;
    };

    background.invert = lib.mkEnableOption "invert wallpaper colors before gowall LUT mapping" // {
      default = false;
    };
  };

  options.gowall = {
    themeJSON = lib.mkOption {
      type = lib.types.path;
      readOnly = true;
      description = "Path to the generated gowall theme JSON file (flavor + accent).";
    };
  };

  config = {
    gowall.themeJSON = themeJSON;
  };
}
