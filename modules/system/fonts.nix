# Font Configuration
#
# This module configures:
# 1. System-wide font packages (JetBrainsMono Nerd Font, Noto fonts)
# 2. Fontconfig defaults (monospace, sans-serif, serif, emoji)
# 3. UI font style toggle (monospace vs sans-serif)
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
#
# Note: Terminal (kitty) and code editors always use fonts.defaults.monospace,
# regardless of uiStyle setting.

{ pkgs, config, lib, ... }:

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
      type = lib.types.enum [ "monospace" "sans-serif" ];
      default = "monospace";
      description = "Font style for UI elements (waybar, dunst, rofi, hyprlock, SDDM, GTK, Qt)";
    };

    ui = lib.mkOption {
      type = lib.types.str;
      default = if config.fonts.defaults.uiStyle == "monospace"
                then config.fonts.defaults.monospace
                else config.fonts.defaults.sansSerif;
      readOnly = true;
      description = "Resolved UI font name based on uiStyle (do not set manually)";
    };

    # Font Size Options
    size = lib.mkOption {
      type = lib.types.int;
      default = 11;
      description = "Default font size for UI elements";
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

  config.fonts = {

    #---------------------------
    # 1. Font Packages
    #---------------------------
    packages = with pkgs; [
      # Nerd Fonts (patched with icons and glyphs)
      nerd-fonts.jetbrains-mono  # Primary monospace font
      nerd-fonts.symbols-only    # Icon font (used by waybar, etc.)

      # Noto Fonts (Google's universal font family)
      noto-fonts              # Sans-serif and serif fonts
      noto-fonts-cjk-sans     # CJK (Chinese, Japanese, Korean) support
      noto-fonts-color-emoji  # Color emoji support
    ];

    #---------------------------
    # 2. Fontconfig Defaults
    #---------------------------
    fontconfig = {
      enable = true;
      defaultFonts = {
        monospace = [ config.fonts.defaults.monospace "Noto Sans Mono" ];
        sansSerif = [ config.fonts.defaults.sansSerif ];
        serif = [ config.fonts.defaults.serif ];
        emoji = [ "Noto Color Emoji" ];
      };
    };
  };
}
