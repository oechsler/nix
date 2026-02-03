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
        default = "lavender";
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
  };

  config = {
    # Catppuccin system-wide theming nutzt die zentralen Werte
    catppuccin = {
      enable = true;
      flavor = config.theme.catppuccin.flavor;
      accent = config.theme.catppuccin.accent;
    };
  };
}
