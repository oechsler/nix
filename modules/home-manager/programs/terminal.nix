{ config, pkgs, fonts, theme, ... }:

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
      size = fonts.size;
    };
    settings = {
      window_padding_width = theme.gaps.outer;
      confirm_os_window_close = 0;
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
    bluetuith
    pulsemixer
  ];

  programs.zoxide = {
    enable = true;
    enableFishIntegration = true;
  };
}
