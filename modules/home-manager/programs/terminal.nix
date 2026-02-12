{ config, pkgs, lib, fonts, theme, features, ... }:

{
  options.terminal.exec = lib.mkOption {
    type = lib.types.str;
    default = "kitty --title";
    readOnly = true;
    description = "Command prefix to launch a TUI app in the terminal (usage: exec 'title' -e 'command')";
  };

  config = {
    programs.kitty = {
      enable = true;
      font = {
        name = fonts.monospace;
        size = fonts.terminalSize;
      };
      settings = {
        window_padding_width = theme.gaps.outer;
        confirm_os_window_close = 0;
      } // lib.optionalAttrs (features.desktop.wm != "hyprland") {
        remember_window_size = "no";
        initial_window_width = "96c";
        initial_window_height = "22c";
      };
      keybindings = {
        "alt+shift+enter" = "send_text all \\x1b-";
      };
    };

    programs.starship = {
      enable = true;
      enableFishIntegration = true;
    };

    programs.eza = {
      enable = true;
      enableFishIntegration = true;
      icons = "auto";
      extraOptions = [ "--group-directories-first" ];
    };

    programs.bat.enable = true;
    programs.gitui.enable = true;
    programs.htop = {
      enable = true;
      settings = {
        tree_view = true;
        sort_key = 1;
      };
    };

    programs.fzf = {
      enable = true;
      enableFishIntegration = true;
    };

    programs.fastfetch.enable = true;

    home.packages = with pkgs; [
      bluetui
      fd
      jq
      pulsemixer
      ripgrep
    ];

    programs.zoxide = {
      enable = true;
      enableFishIntegration = true;
    };
  };
}
