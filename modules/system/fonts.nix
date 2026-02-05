{ pkgs, config, lib, ... }:

{
  options.fonts.defaults = {
    monospace = lib.mkOption {
      type = lib.types.str;
      default = "JetBrainsMono Nerd Font";
    };
    sansSerif = lib.mkOption {
      type = lib.types.str;
      default = "Noto Sans";
    };
    serif = lib.mkOption {
      type = lib.types.str;
      default = "Noto Serif";
    };
    size = lib.mkOption {
      type = lib.types.int;
      default = 11;
    };
    terminalSize = lib.mkOption {
      type = lib.types.int;
      default = config.fonts.defaults.size;
      description = "Terminal (Kitty) font size – defaults to fonts.defaults.size";
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
