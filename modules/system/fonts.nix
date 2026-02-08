{ pkgs, config, lib, ... }:

# Font configuration for the entire system.
#
# fonts.defaults.uiStyle controls which font style is used for UI elements:
#   "monospace"  → uses fonts.defaults.monospace (default, hacker look)
#   "sans-serif" → uses fonts.defaults.sansSerif (traditional desktop look)
#
# The resolved font name is available as fonts.defaults.ui (read-only)
# and is used by: waybar, dunst, rofi, hyprlock, SDDM, GTK and Qt apps.
#
# Terminal (kitty) and code editors always use fonts.defaults.monospace,
# regardless of uiStyle.
{
  options.fonts.defaults = {
    monospace = lib.mkOption {
      type = lib.types.str;
      default = "JetBrainsMono Nerd Font";
      description = "Monospace font – used for terminal, code editors, and UI when uiStyle = monospace";
    };
    sansSerif = lib.mkOption {
      type = lib.types.str;
      default = "Noto Sans";
      description = "Sans-serif font – used for UI when uiStyle = sans-serif";
    };
    serif = lib.mkOption {
      type = lib.types.str;
      default = "Noto Serif";
      description = "Serif font – used as fontconfig default";
    };
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
      description = "Resolved UI font name based on uiStyle – do not set manually";
    };
    size = lib.mkOption {
      type = lib.types.int;
      default = 11;
      description = "Default font size for UI elements";
    };
    terminalSize = lib.mkOption {
      type = lib.types.int;
      default = config.fonts.defaults.size;
      description = "Terminal (kitty) font size – defaults to fonts.defaults.size";
    };
  };

  config.fonts = {
    packages = with pkgs; [
      nerd-fonts.jetbrains-mono
      nerd-fonts.fira-code
      nerd-fonts.symbols-only
      noto-fonts
      noto-fonts-cjk-sans
      noto-fonts-color-emoji
    ];

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
