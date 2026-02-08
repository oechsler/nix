{ config, pkgs, lib, fonts, theme, features, ... }:

{
  programs.fish = {
    enable = true;
    interactiveShellInit = "set fish_greeting";
    shellAliases = {
      cat = "bat";
      ll = "eza --long";
      lt = "eza --tree --level 1";
      rm = "trash-put";
      trash = "trash-list";
    };
    functions = {
      cd = {
        wraps = "z";
        body = ''
          __zoxide_z $argv
          and lt
        '';
      };
      cf = {
        wraps = "zi";
        body = "__zoxide_zi $argv";
      };
    };
  };

  home.sessionVariables.PAGER = "less";

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
    pulsemixer
  ];

  programs.zoxide = {
    enable = true;
    enableFishIntegration = true;
  };
}
