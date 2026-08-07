# Tmux Configuration
#
# This module configures tmux as the terminal multiplexer.
#
# Features:
# - Catppuccin theme
# - Fish shell integration
# - Vi key mode
# - Alt-based keybindings (matching Hyprland)
# - No prefix key (uses Alt directly)
# - Window/pane navigation with Alt+H/J/K/L
# - Window creation/closing with Alt+Enter/Q
#
# Keybindings:
#   Alt+H/J/K/L - Navigate between panes
#   Alt+Enter - New window
#   Alt+Q - Kill pane
#   Alt+1-9 - Switch to window 1-9

{ config, pkgs, ... }:

{
  catppuccin.tmux.extraConfig = ''
    set -g @catppuccin_window_status_style "rounded"
    set -g @catppuccin_window_text " #{pane_current_command}"
    set -g @catppuccin_window_current_text " #{pane_current_command}"
    set -g @catppuccin_window_number "#I"
    set -g @catppuccin_window_current_number "#I"
    set -g @catppuccin_window_text_color "#{@thm_surface_0}"
    set -g @catppuccin_window_number_color "#{@thm_overlay_2}"
    set -g @catppuccin_window_current_text_color "#{@thm_surface_1}"
    set -g @catppuccin_window_current_number_color "#{@thm_${config.catppuccin.accent}}"
  '';

  programs.tmux = {
    enable = true;
    shell = "${pkgs.fish}/bin/fish";
    terminal = "tmux-256color";
    escapeTime = 0;
    baseIndex = 1;
    keyMode = "vi";
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

      bind -n M-C-h resize-pane -L 5
      bind -n M-C-j resize-pane -D 5
      bind -n M-C-k resize-pane -U 5
      bind -n M-C-l resize-pane -R 5

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
      bind -n M-n command-prompt -I '#{session_name}' -p 'Session name:' 'rename-session "%%"'
      bind -n M-N command-prompt -I '#{window_name}' -p 'Window name:' 'rename-window "%%"'
      bind -n M-W kill-session

      # Move pane/window (Alt+M, then key)
      #   s - Move current window to selected session
      #   1-0 - Move current pane to window 1-10
      bind -n M-m switch-client -T move
      bind -T move s choose-tree -s -F '#{session_name}' 'move-window -t "%%"'
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
      set -g allow-passthrough on

      # Status bar (after catppuccin plugin)
      set -g status 2
      set -g status-style "bg=default"
      set -g message-style "fg=#{@thm_fg},bg=#{@thm_surface_0},fill=#{@thm_surface_0},align=left"
      set -g message-command-style "fg=#{@thm_fg},bg=#{@thm_surface_0},fill=#{@thm_surface_0},align=left"
      set -g message-format "#[fg=#{@thm_${config.catppuccin.accent}},bg=#{@thm_surface_0}]#[fg=#{@thm_crust},bg=#{@thm_${config.catppuccin.accent}}] #[fg=#{@thm_fg},bg=#{@thm_surface_0}] #{message}"
      set -gF status-format[1] "#{status-format[0]}"
      set -g status-format[0] ""
      set -g status-left-length 20
      set -g status-left "#[fg=#{@thm_${config.catppuccin.accent}},bg=default]#[fg=#{@thm_crust},bg=#{@thm_${config.catppuccin.accent}}] #[fg=#{@thm_fg},bg=#{@thm_surface_0}] #S#[fg=#{@thm_surface_0},bg=default] "
      set -g status-right "#[fg=#{@thm_${config.catppuccin.accent}},bg=default]#[fg=#{@thm_crust},bg=#{@thm_${config.catppuccin.accent}}] #[fg=#{@thm_fg},bg=#{@thm_surface_0}] #{=/24/…:#{s|$HOME|~|:pane_current_path}}#[fg=#{@thm_surface_0},bg=default] #[fg=#{@thm_${config.catppuccin.accent}},bg=default]#[fg=#{@thm_crust},bg=#{@thm_${config.catppuccin.accent}}]󰒋 #[fg=#{@thm_fg},bg=#{@thm_surface_0}] #h#[fg=#{@thm_surface_0},bg=default]"
    '';
  };
}
