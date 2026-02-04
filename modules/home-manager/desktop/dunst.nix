{ config, pkgs, lib, fonts, ... }:

let
  # Palette dynamisch aus dem Catppuccin-Modul laden (alle Flavors + Accents)
  palette = (lib.importJSON "${config.catppuccin.sources.palette}/palette.json").${config.catppuccin.flavor}.colors;
  accent = palette.${config.catppuccin.accent}.hex;
in
{
  # Basis-Farben kommen vom Catppuccin-Modul (catppuccin.dunst.enable = true)
  # Accent-Override nötig weil das Modul immer Blue hardcodet
  services.dunst = {
    enable = true;
    settings = {
      global = {
        # Aussehen - passend zu Hyprland
        width = 350;
        height = "(0, 300)";
        offset = "16x16";
        origin = "top-right";
        corner_radius = 16;
        frame_width = 2;
        frame_color = lib.mkForce accent;
        highlight = lib.mkForce accent;
        separator_color = "frame";
        gap_size = 8;

        # Schrift
        font = "${fonts.monospace} 10";

        # Icons via Nerd Font Glyphs im Text
        icon_position = "off";

        # Text
        alignment = "center";
        vertical_alignment = "center";
        word_wrap = true;
        ellipsize = "end";
        markup = "full";
        format = "<b>%s</b>\\n%b";
        padding = 12;
        horizontal_padding = 16;

        # Verhalten
        sort = true;
        idle_threshold = 120;
        show_age_threshold = 60;
        sticky_history = true;
        history_length = 20;
        show_indicators = false;

        # Progress Bar
        progress_bar = true;
        progress_bar_height = 12;
        progress_bar_frame_width = 0;
        progress_bar_min_width = 250;
        progress_bar_max_width = 300;
        progress_bar_corner_radius = 6;

        # Maus-Aktionen
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
