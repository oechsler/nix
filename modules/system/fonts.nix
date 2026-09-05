# Font Configuration
#
# This module configures the shared font family options, installs the font
# packages needed by the system, configures desktop Fontconfig defaults, and
# generates the Linux VT font from the selected monospace family.
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
# Linux VTs use a generated PSF2 bitmap based on fonts.monospace.
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
  # means changing fonts.monospace also changes the generated VT font.
  monospaceFamilyQuery = lib.escapeShellArg config.fonts.monospace;
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
