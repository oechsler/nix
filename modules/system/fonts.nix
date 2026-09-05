# Font Configuration
#
# This module configures the shared font family options, installs the font
# packages needed by the system, configures desktop Fontconfig defaults, and
# generates the Linux VT font from the selected monospace family.
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
# The resolved UI font is available as fonts.defaults.ui (read-only) and is
# used by waybar, dunst, rofi, hyprlock, SDDM, GTK, and Qt apps.
# Linux VTs use a generated PSF2 bitmap based on fonts.defaults.monospace.
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
  # Keep these packages available on headless hosts as well: the VT font is
  # generated from the installed font collection during the system build.
  fontPackages = with pkgs; [
    nerd-fonts.jetbrains-mono
    nerd-fonts.symbols-only
    noto-fonts
    noto-fonts-cjk-sans
    noto-fonts-color-emoji
  ];
  fontConfig = pkgs.makeFontsConf { fontDirectories = config.fonts.packages; };
  # Fontconfig resolves the configured family to the actual font file. This
  # means changing fonts.defaults.monospace also changes the generated VT font.
  monospaceFamilyQuery = lib.escapeShellArg config.fonts.defaults.monospace;
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
        sourceFont="$(fc-match -f '%{file}' ${monospaceFamilyQuery})"
        test -s "$sourceFont"
        # Linux VTs require a fixed-width PSF font. A VT cannot reproduce the
        # terminal's point size exactly, so use a stable 8-column/16-row raster.
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
    # Font Family
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

    # UI Style
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

    # Font Sizes
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
      description = "Terminal (Kitty) font size; Linux VT uses its own fixed pixel grid";
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
      # Font packages are installed on all hosts because the VT font is built
      # from this collection. Fontconfig itself is desktop-only.
      packages = fontPackages;

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
