# Dunst Configuration (Notification Daemon)
#
# This module configures dunst as the notification daemon for Hyprland.
#
# Features:
# - Catppuccin color scheme integration
# - Theme-aware styling (corner radius, gaps, borders)
# - Multi-monitor support (shows on primary monitor)
# - Progress bars (volume, brightness notifications)
# - Icon support (32-64px)
# - Urgency levels (low, normal, critical)
#
# Notification urgency levels:
# - Low: 5s timeout, accent color border
# - Normal: 10s timeout, accent color border
# - Critical: No timeout (manual close), red border
#
# Mouse actions:
# - Left click: Close notification
# - Middle click: Perform action + close
# - Right click: Close all notifications
#
# Position: Top-right corner with theme.gaps.outer margin

{ config, lib, fonts, theme, displays, ... }:

let
  # Extract Catppuccin palette colors
  palette = (lib.importJSON "${config.catppuccin.sources.palette}/palette.json").${config.catppuccin.flavor}.colors;
  accent = palette.${config.catppuccin.accent}.hex;

  # Show notifications on primary monitor
  primaryMonitor = lib.head displays.monitors;
in
{
  #===========================
  # Configuration
  #===========================

  services.dunst = {
    enable = true;
    settings = {

      #---------------------------
      # Global Settings
      #---------------------------
      global = {
        monitor = primaryMonitor.name;
        width = 350;
        height = "(0, 300)";
        offset = "${toString theme.gaps.outer}x${toString theme.gaps.outer}";
        origin = "top-right";
        corner_radius = theme.radius.default;
        frame_width = theme.border.width;
        frame_color = lib.mkForce accent;
        highlight = lib.mkForce accent;
        separator_color = "frame";
        gap_size = theme.gaps.inner;

        font = "${fonts.ui} 10";
        icon_position = "left";
        min_icon_size = 32;
        max_icon_size = 64;

        alignment = "left";
        vertical_alignment = "center";
        word_wrap = true;
        ellipsize = "end";
        markup = "full";
        format = "<b>%s</b>\\n%b";
        padding = theme.gaps.inner + 4;
        horizontal_padding = theme.gaps.outer;

        sort = true;
        idle_threshold = 120;
        show_age_threshold = 60;
        sticky_history = true;
        history_length = 20;
        show_indicators = false;

        progress_bar = true;
        progress_bar_height = theme.gaps.inner + 4;
        progress_bar_frame_width = 0;
        progress_bar_min_width = 250;
        progress_bar_max_width = 300;
        progress_bar_corner_radius = theme.radius.small;

        mouse_left_click = "close_current";
        mouse_middle_click = "do_action, close_current";
        mouse_right_click = "close_all";
      };

      #---------------------------
      # Urgency Levels
      #---------------------------

      # Low urgency (e.g., system info)
      urgency_low = {
        frame_color = lib.mkForce accent;
        highlight = lib.mkForce accent;
        timeout = 5;
      };

      urgency_normal = {
        frame_color = lib.mkForce accent;
        highlight = lib.mkForce accent;
        timeout = 10;
      };

      urgency_critical = {
        frame_color = lib.mkForce palette.red.hex;
        highlight = lib.mkForce palette.red.hex;
        timeout = 0;
      };
    };
  };
}
