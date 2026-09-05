# Font Configuration
#
# This module configures:
# 1. System-wide font packages (JetBrainsMono Nerd Font, Noto fonts)
# 2. Fontconfig defaults (monospace, sans-serif, serif, emoji)
# 3. Linux VT font generated from the configured monospace font
# 4. UI font style toggle (monospace vs sans-serif)
#
# Configuration options:
#   fonts.defaults.uiStyle = "monospace";      # UI font style (default: "monospace")
#   fonts.defaults.monospace = "JetBrainsMono Nerd Font";  # Monospace font (default)
#   fonts.defaults.sansSerif = "Noto Sans";    # Sans-serif font (default)
#   fonts.defaults.size = 11;                  # Default font size (default: 11)
#
# UI font style (fonts.defaults.uiStyle):
#   "monospace"  → Uses fonts.defaults.monospace (hacker/terminal aesthetic)
#   "sans-serif" → Uses fonts.defaults.sansSerif (traditional desktop aesthetic)
#
# The resolved UI font is available as fonts.defaults.ui (read-only).
# Used by: waybar, dunst, rofi, hyprlock, SDDM, GTK, and Qt apps.
# Linux VTs use a generated PSF2 bitmap based on the configured monospace font.
#
# Note: Terminal (kitty) and code editors always use fonts.defaults.monospace,
# regardless of uiStyle setting.

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
  fontConfig = pkgs.makeFontsConf { fontDirectories = config.fonts.packages; };
  monospaceFamily = lib.escapeShellArg config.fonts.defaults.monospace;
  consoleFont =
    pkgs.runCommand "linux-vt-consolefont"
      {
        nativeBuildInputs = [
          pkgs.fontconfig
          pkgs.otf2bdf
          pkgs.bdf2psf
        ];
        FONTCONFIG_FILE = fontConfig;
      }
      ''
        mkdir -p $out/share/consolefonts
        sourceFont="$(fc-match -f '%{file}' ${monospaceFamily})"
        test -s "$sourceFont"
        # Linux VTs require a fixed-width PSF font. The 9pt raster is the closest
        # stable 8-column rendering of the default 11pt terminal font.
        otf2bdf -p 9 -r 100 -c C -l '0_255' \
          -o font.bdf \
          "$sourceFont" \
          || test -s font.bdf
        bdf2psf --fb \
          font.bdf \
          ${pkgs.bdf2psf}/share/bdf2psf/standard.equivalents \
          ${pkgs.bdf2psf}/share/bdf2psf/ascii.set \
          256 \
          $out/share/consolefonts/linux-vt-consolefont.psf
      '';
in

{
  #===========================
  # Options
  #===========================

  options.fonts.defaults = {
    # Font Family Options
    monospace = lib.mkOption {
      type = lib.types.str;
      default = "JetBrainsMono Nerd Font";
      description = "Monospace font (terminal, code editors, UI when uiStyle = monospace)";
    };

    sansSerif = lib.mkOption {
      type = lib.types.str;
      default = "Noto Sans";
      description = "Sans-serif font (UI when uiStyle = sans-serif)";
    };

    serif = lib.mkOption {
      type = lib.types.str;
      default = "Noto Serif";
      description = "Serif font (fontconfig default)";
    };

    # UI Font Style Toggle
    uiStyle = lib.mkOption {
      type = lib.types.enum [
        "monospace"
        "sans-serif"
      ];
      default = "monospace";
      description = "Font style for UI elements (waybar, dunst, rofi, hyprlock, SDDM, GTK, Qt)";
    };

    ui = lib.mkOption {
      type = lib.types.str;
      default =
        if config.fonts.defaults.uiStyle == "monospace" then
          config.fonts.defaults.monospace
        else
          config.fonts.defaults.sansSerif;
      readOnly = true;
      description = "Resolved UI font name based on uiStyle (do not set manually)";
    };

    # Font Size Options
    size = lib.mkOption {
      type = lib.types.int;
      default = 11;
      description = "Default font size for UI elements";
    };

    uiPixelSize = lib.mkOption {
      type = lib.types.int;
      default = builtins.floor (config.fonts.defaults.size * 4 / 3);
      readOnly = true;
      description = "CSS pixel equivalent of the typographic UI size";
    };

    terminalSize = lib.mkOption {
      type = lib.types.int;
      default = config.fonts.defaults.size;
      description = "Terminal (kitty) font size (defaults to fonts.defaults.size)";
    };
  };

  #===========================
  # Configuration
  #===========================

  config = {
    console = {
      font = "${consoleFont}/share/consolefonts/linux-vt-consolefont.psf";
    };

    fonts = {

      #---------------------------
      # 1. Font Packages
      #---------------------------
      packages = fontPackages;

      #---------------------------
      # 2. Fontconfig Defaults
      #---------------------------
      fontconfig = lib.mkIf config.features.desktop.enable {
        enable = true;
        defaultFonts = {
          monospace = [
            config.fonts.defaults.monospace
            "Noto Sans Mono"
          ];
          sansSerif = [ config.fonts.defaults.sansSerif ];
          serif = [ config.fonts.defaults.serif ];
          emoji = [ "Noto Color Emoji" ];
        };
      };
    };
  };
}
