# MangoHud Configuration
#
# This module configures the Home Manager MangoHud module with the selected
# Catppuccin flavor. It writes ~/.config/MangoHud/MangoHud.conf for normal
# desktop gaming.
#
# In Steam Machine mode, the per-session MANGOHUD_CONFIGFILE override
# (with no_display, set in gaming.nix) takes precedence.

{
  config,
  features,
  lib,
  ...
}:

let
  palette =
    (lib.importJSON "${config.catppuccin.sources.palette}/palette.json")
    .${config.catppuccin.flavor}.colors;

  hex = name: lib.removePrefix "#" palette.${name}.hex;
in
{
  config = lib.mkIf features.gaming.enable {
    programs.mangohud = {
      enable = true;
      settings = {
        legacy_layout = false;
        round_corners = 10;
        background_alpha = 0.8;
        background_color = hex "base";
        table_columns = 3;

        font_size = 24;
        text_color = hex "text";
        text_outline_color = hex "surface0";

        gpu_text = "GPU";
        gpu_stats = true;
        gpu_temp = true;
        gpu_color = hex "green";
        gpu_load_change = true;
        gpu_load_color = [
          (hex "text")
          (hex "peach")
          (hex "red")
        ];

        cpu_text = "CPU";
        cpu_stats = true;
        cpu_temp = true;
        cpu_color = hex "blue";
        cpu_load_change = true;
        cpu_load_color = [
          (hex "text")
          (hex "peach")
          (hex "red")
        ];

        ram = true;
        ram_color = hex "pink";

        engine_color = hex "red";

        fps = true;
        fps_color_change = [
          (hex "red")
          (hex "yellow")
          (hex "green")
        ];

        wine = true;
        wine_color = hex "red";
        winesync = true;

        frame_timing = true;
        frametime_color = hex "green";

        arch = true;
        fps_limit_method = "early";
        toggle_fps_limit = "Shift_L+F1";
      };
    };
  };
}
