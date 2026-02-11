{ config, pkgs, lib, fonts, theme, features, ... }:

{
  programs.fish = {
    enable = true;
    interactiveShellInit = ''
      set fish_greeting
      # Auto-attach tmux on SSH sessions
      if set -q SSH_CONNECTION; and not set -q TMUX
        tmux new-session -A -s ssh
      end
    '';
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
      enabled_layouts = "splits,stack";
      tab_bar_style = "powerline";
    } // lib.optionalAttrs (features.desktop.wm != "hyprland") {
      remember_window_size = "no";
      initial_window_width = "96c";
      initial_window_height = "22c";
    };
    keybindings = {
      # Focus between windows (≈ Super+H/J/K/L in Hyprland)
      "alt+h" = "neighboring_window left";
      "alt+j" = "neighboring_window bottom";
      "alt+k" = "neighboring_window top";
      "alt+l" = "neighboring_window right";

      # Move windows (≈ Super+Shift+H/J/K/L in Hyprland)
      "alt+shift+h" = "move_window left";
      "alt+shift+j" = "move_window down";
      "alt+shift+k" = "move_window up";
      "alt+shift+l" = "move_window right";

      # Splits / close window
      "alt+enter" = "launch --cwd=current --location=vsplit";
      "alt+shift+enter" = "launch --cwd=current --location=hsplit";
      "alt+q" = "close_window";

      # Fullscreen toggle
      "alt+f" = "toggle_layout stack";

      # Resize
      "alt+r" = "start_resizing_window";

      # Tab navigation (≈ Super+1-0 workspaces in Hyprland)
      "alt+1" = "goto_tab 1";
      "alt+2" = "goto_tab 2";
      "alt+3" = "goto_tab 3";
      "alt+4" = "goto_tab 4";
      "alt+5" = "goto_tab 5";
      "alt+6" = "goto_tab 6";
      "alt+7" = "goto_tab 7";
      "alt+8" = "goto_tab 8";
      "alt+9" = "goto_tab 9";
      "alt+0" = "goto_tab 10";

      # Tab management
      "alt+t" = "new_tab_with_cwd";
      "alt+w" = "close_tab";

      # Move window to tab (≈ Super+Shift+1-0 in Hyprland)
      "alt+shift+1" = "detach_window tab-1";
      "alt+shift+2" = "detach_window tab-2";
      "alt+shift+3" = "detach_window tab-3";
      "alt+shift+4" = "detach_window tab-4";
      "alt+shift+5" = "detach_window tab-5";
      "alt+shift+6" = "detach_window tab-6";
      "alt+shift+7" = "detach_window tab-7";
      "alt+shift+8" = "detach_window tab-8";
      "alt+shift+9" = "detach_window tab-9";
      "alt+shift+0" = "detach_window tab-10";
    };
  };

  programs.tmux = {
    enable = true;
    shell = "${pkgs.fish}/bin/fish";
    terminal = "tmux-256color";
    escapeTime = 0;
    baseIndex = 1;
    keyMode = "vi";
    plugins = with pkgs.tmuxPlugins; [
      {
        plugin = catppuccin;
        extraConfig = ''
          set -g @catppuccin_flavor "${config.catppuccin.flavor}"
        '';
      }
    ];
    extraConfig = ''
      # Alt-based keybindings (matching kitty/Hyprland)
      set -g prefix None
      unbind C-b

      # Focus between panes (≈ Alt+H/J/K/L)
      bind -n M-h select-pane -L
      bind -n M-j select-pane -D
      bind -n M-k select-pane -U
      bind -n M-l select-pane -R

      # Move panes (≈ Alt+Shift+H/J/K/L)
      bind -n M-H swap-pane -d -t '{left-of}'
      bind -n M-J swap-pane -d -t '{down-of}'
      bind -n M-K swap-pane -d -t '{up-of}'
      bind -n M-L swap-pane -d -t '{right-of}'

      # Splits / close pane
      bind -n M-Enter split-window -h -c '#{pane_current_path}'
      bind -n M-S-Enter split-window -v -c '#{pane_current_path}'
      bind -n M-q kill-pane

      # Fullscreen toggle
      bind -n M-f resize-pane -Z

      # Resize
      bind -n M-r switch-client -T resize
      bind -T resize h resize-pane -L 5 \; switch-client -T resize
      bind -T resize j resize-pane -D 5 \; switch-client -T resize
      bind -T resize k resize-pane -U 5 \; switch-client -T resize
      bind -T resize l resize-pane -R 5 \; switch-client -T resize

      # Tab (window) navigation (≈ Alt+1-0)
      bind -n M-1 select-window -t 1
      bind -n M-2 select-window -t 2
      bind -n M-3 select-window -t 3
      bind -n M-4 select-window -t 4
      bind -n M-5 select-window -t 5
      bind -n M-6 select-window -t 6
      bind -n M-7 select-window -t 7
      bind -n M-8 select-window -t 8
      bind -n M-9 select-window -t 9
      bind -n M-0 select-window -t 10

      # Tab management
      bind -n M-t new-window -c '#{pane_current_path}'
      bind -n M-w kill-window

      # Move pane to window (≈ Alt+Shift+1-0)
      bind -n M-! join-pane -t :1
      bind -n M-@ join-pane -t :2
      bind -n M-'#' join-pane -t :3
      bind -n M-'$' join-pane -t :4
      bind -n M-% join-pane -t :5
      bind -n M-^ join-pane -t :6
      bind -n M-& join-pane -t :7
      bind -n M-* join-pane -t :8
      bind -n M-( join-pane -t :9
      bind -n M-) join-pane -t :10

      # Mouse support
      set -g mouse on
    '';
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
