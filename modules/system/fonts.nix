# Font Configuration
#
# This module configures the shared font family options, installs the font
# packages needed by the system, configures desktop Fontconfig defaults, and
# selects a stable console font size for Linux VTs.
#
# Configuration options:
#   fonts.ui.style = "monospace";      # UI font style (default: "monospace")
#   fonts.monospace = "JetBrainsMono Nerd Font";  # Monospace font (default)
#   fonts.sansSerif = "Noto Sans";    # Sans-serif font (default)
#   fonts.ui.size = 11;               # Default UI font size (default: 11)
#   fonts.terminal.size = 11;         # Terminal font size (default: UI size)
#
# UI font style (fonts.ui.style):
#   "monospace"  → Uses fonts.monospace (hacker/terminal aesthetic)
#   "sans-serif" → Uses fonts.sansSerif (traditional desktop aesthetic)
#
# The resolved UI font is available as fonts.ui.font (read-only) and is
# used by waybar, dunst, rofi, hyprlock, SDDM, GTK, and Qt apps.
# Linux VTs use the packaged Terminus console font at the closest fixed size.
#
# Note: Terminal (kitty) and code editors always use fonts.monospace,
# regardless of fonts.ui.style.

{
  pkgs,
  config,
  lib,
  ...
}:

let
  fontPackages = with pkgs; [
    nerd-fonts.jetbrains-mono
    nerd-fonts.symbols-only
    noto-fonts
    noto-fonts-cjk-sans
    noto-fonts-color-emoji
  ];
  consoleFont = {
    "10" = "ter-114n";
    "11" = "ter-116n";
    "12" = "ter-118n";
    "13" = "ter-120n";
    "14" = "ter-122n";
    "15" = "ter-124n";
    "16" = "ter-128n";
  };
in

{
  #===========================
  # Options
  #===========================

  options.fonts = {
    # Font Family
    monospace = lib.mkOption {
      type = lib.types.str;
      default = "JetBrainsMono Nerd Font";
      description = "Monospace font (terminal, code editors, UI when fonts.ui.style = monospace)";
    };

    sansSerif = lib.mkOption {
      type = lib.types.str;
      default = "Noto Sans";
      description = "Sans-serif font (UI when fonts.ui.style = sans-serif)";
    };

    serif = lib.mkOption {
      type = lib.types.str;
      default = "Noto Serif";
      description = "Serif font (fontconfig default)";
    };

    ui = {
      style = lib.mkOption {
        type = lib.types.enum [
          "monospace"
          "sans-serif"
        ];
        default = "monospace";
        description = "Font style for UI elements";
      };

      font = lib.mkOption {
        type = lib.types.str;
        default =
          if config.fonts.ui.style == "monospace" then config.fonts.monospace else config.fonts.sansSerif;
        readOnly = true;
        description = "Resolved UI font name based on fonts.ui.style";
      };

      size = lib.mkOption {
        type = lib.types.int;
        default = 11;
        description = "Default font size for UI elements";
      };

      pixelSize = lib.mkOption {
        type = lib.types.int;
        default = builtins.floor (config.fonts.ui.size * 4 / 3);
        readOnly = true;
        description = "CSS pixel equivalent of the UI font size";
      };
    };

    terminal.size = lib.mkOption {
      type = lib.types.int;
      default = config.fonts.ui.size;
      description = "Terminal (Kitty) font size; Linux VT uses its own fixed pixel grid";
    };
  };

  #===========================
  # Configuration
  #===========================

  config = {
    console = {
      packages = [ pkgs.terminus_font ];
      font = consoleFont.${toString config.fonts.terminal.size} or consoleFont."11";
    };

    fonts = {
      # Font packages are installed on all hosts. Fontconfig itself is desktop-only.
      packages = fontPackages;

      fontconfig = lib.mkIf config.features.desktop.enable {
        enable = true;
        defaultFonts = {
          monospace = [
            config.fonts.monospace
            "Noto Sans Mono"
          ];
          sansSerif = [ config.fonts.sansSerif ];
          serif = [ config.fonts.serif ];
          emoji = [ "Noto Color Emoji" ];
        };
      };
    };
  };
}
