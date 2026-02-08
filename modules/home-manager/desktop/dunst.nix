{ config, pkgs, lib, fonts, theme, displays, ... }:

let
  palette = (lib.importJSON "${config.catppuccin.sources.palette}/palette.json").${config.catppuccin.flavor}.colors;
  accent = palette.${config.catppuccin.accent}.hex;
  primaryMonitor = lib.head displays.monitors;
in
{
  services.dunst = {
    enable = true;
    settings = {
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

        font = "${fonts.monospace} 10";
        icon_position = "off";

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
