{ config, pkgs, ... }:

{
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
          set -g @catppuccin_window_status_style "basic"
          set -g @catppuccin_window_text "#{pane_current_command}"
          set -g @catppuccin_window_current_text "#{pane_current_command}"
          set -g @catppuccin_status_left ""
        '';
      }
    ];
    extraConfig = ''
      # Alt-based keybindings (matching Hyprland)
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

      bind -n M-Enter split-window -h -c '#{pane_current_path}'
      bind -n M-- split-window -v -c '#{pane_current_path}'
      bind -n M-q kill-pane

      bind -n M-Space if-shell -F "#{==:#{pane_width},#{window_width}}" "select-layout even-horizontal" "select-layout even-vertical"
      bind -n M-f resize-pane -Z

      bind -n M-r switch-client -T resize
      bind -T resize h resize-pane -L 5 \; switch-client -T resize
      bind -T resize j resize-pane -D 5 \; switch-client -T resize
      bind -T resize k resize-pane -U 5 \; switch-client -T resize
      bind -T resize l resize-pane -R 5 \; switch-client -T resize

      # Tab (window) navigation (≈ Alt+1-0)
      bind -n M-1 run-shell "tmux select-window -t 1 || tmux new-window -t 1"
      bind -n M-2 run-shell "tmux select-window -t 2 || tmux new-window -t 2"
      bind -n M-3 run-shell "tmux select-window -t 3 || tmux new-window -t 3"
      bind -n M-4 run-shell "tmux select-window -t 4 || tmux new-window -t 4"
      bind -n M-5 run-shell "tmux select-window -t 5 || tmux new-window -t 5"
      bind -n M-6 run-shell "tmux select-window -t 6 || tmux new-window -t 6"
      bind -n M-7 run-shell "tmux select-window -t 7 || tmux new-window -t 7"
      bind -n M-8 run-shell "tmux select-window -t 8 || tmux new-window -t 8"
      bind -n M-9 run-shell "tmux select-window -t 9 || tmux new-window -t 9"
      bind -n M-0 run-shell "tmux select-window -t 10 || tmux new-window -t 10"

      bind -n M-t new-window -c '#{pane_current_path}'
      bind -n M-w kill-window

      bind -n M-s choose-tree -s
      bind -n M-S new-session
      bind -n M-W kill-session

      # Move pane to window (Alt+M, then 1-0)
      bind -n M-m switch-client -T move
      bind -T move 1 join-pane -t :1
      bind -T move 2 join-pane -t :2
      bind -T move 3 join-pane -t :3
      bind -T move 4 join-pane -t :4
      bind -T move 5 join-pane -t :5
      bind -T move 6 join-pane -t :6
      bind -T move 7 join-pane -t :7
      bind -T move 8 join-pane -t :8
      bind -T move 9 join-pane -t :9
      bind -T move 0 join-pane -t :10

      set -g mouse on

      # Status (after catppuccin plugin)
      set -g status-right " #{=/30/…:#{s|$HOME|~|:pane_current_path}}  #h "
    '';
  };
}
