{ pkgs, config, lib, ... }:

{
  options.theme = {
    catppuccin = {
      flavor = lib.mkOption {
        type = lib.types.enum [ "latte" "frappe" "macchiato" "mocha" ];
        default = "mocha";
        description = "Catppuccin flavor";
      };
      accent = lib.mkOption {
        type = lib.types.enum [
          "blue" "flamingo" "green" "lavender" "maroon" "mauve"
          "peach" "pink" "red" "rosewater" "sapphire" "sky" "teal" "yellow"
        ];
        default = "mauve";
        description = "Catppuccin accent color";
      };
    };

    icons = {
      name = lib.mkOption {
        type = lib.types.str;
        default = if config.theme.catppuccin.flavor == "latte"
                  then "Papirus-Light"
                  else "Papirus-Dark";
        description = "Icon theme name";
      };
      package = lib.mkOption {
        type = lib.types.package;
        default = pkgs.catppuccin-papirus-folders.override {
          flavor = config.theme.catppuccin.flavor;
          accent = config.theme.catppuccin.accent;
        };
        description = "Icon theme package";
      };
    };

    cursor = {
      name = lib.mkOption {
        type = lib.types.str;
        default = if config.theme.catppuccin.flavor == "latte"
                  then "Breeze_Light"
                  else "breeze_cursors";
        description = "Cursor theme name";
      };
      package = lib.mkOption {
        type = lib.types.package;
        default = pkgs.kdePackages.breeze;
        description = "Cursor theme package";
      };
      size = lib.mkOption {
        type = lib.types.int;
        default = 24;
        description = "Cursor size";
      };
    };

    scale = lib.mkOption {
      type = lib.types.float;
      default = 1.0;
      description = "DPI/Monitor scale factor";
    };

    radius = {
      small = lib.mkOption {
        type = lib.types.int;
        default = 6;
        description = "Small border radius (progress bars, small elements)";
      };
      default = lib.mkOption {
        type = lib.types.int;
        default = 16;
        description = "Default border radius (windows, panels, notifications)";
      };
    };

    gaps = {
      inner = lib.mkOption {
        type = lib.types.int;
        default = 8;
        description = "Inner gaps (between windows)";
      };
      outer = lib.mkOption {
        type = lib.types.int;
        default = 16;
        description = "Outer gaps (screen edges)";
      };
    };

    border = {
      width = lib.mkOption {
        type = lib.types.int;
        default = 2;
        description = "Border width";
      };
    };

    wallpaper = lib.mkOption {
      type = lib.types.path;
      default = ../../backgrounds/Cloudsnight.jpg;
      description = "Desktop wallpaper image";
    };
  };

  config = {
    catppuccin = {
      enable = true;
      flavor = config.theme.catppuccin.flavor;
      accent = config.theme.catppuccin.accent;
    };
  };
}
