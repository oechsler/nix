# MangoHud Configuration
#
# This module generates a Catppuccin-themed MangoHud config at
# ~/.config/MangoHud/MangoHud.conf.
#
# The config adapts to the selected Catppuccin flavor:
#   - mocha, macchiato, frappe, latte
#
# In Steam Machine mode, the per-session MANGOHUD_CONFIGFILE override
# (with no_display, set in gaming.nix) takes precedence, so this
# themed config is used during normal desktop gaming only.

{
  config,
  features,
  lib,
  ...
}:

let
  cfg = config.programs.mangohud;

  palette =
    (lib.importJSON "${config.catppuccin.sources.palette}/palette.json")
    .${config.catppuccin.flavor}.colors;

  hex = name: lib.removePrefix "#" palette.${name}.hex;

  genMangoHudConfig = ''
    legacy_layout=false
    round_corners=10
    background_alpha=0.8
    background_color=${hex "base"}
    table_columns=3

    ## Text ##
    font_size=24
    text_color=${hex "text"}
    text_outline_color=${hex "surface0"}

    ## GPU ##
    gpu_text=GPU
    gpu_stats
    gpu_temp
    gpu_color=${hex "green"}
    gpu_load_change
    gpu_load_color=${hex "text"},${hex "peach"},${hex "red"}

    ## CPU ##
    cpu_text=CPU
    cpu_stats
    cpu_temp
    cpu_color=${hex "blue"}
    cpu_load_change
    cpu_load_color=${hex "text"},${hex "peach"},${hex "red"}

    ## RAM ##
    ram
    ram_color=${hex "pink"}

    ## ENGINE ##
    engine_color=${hex "red"}

    ## FPS ##
    fps
    fps_color_change=${hex "red"},${hex "yellow"},${hex "green"}

    ## Wine ##
    wine
    wine_color=${hex "red"}
    winesync

    ## Frame timing ##
    frame_timing
    frametime_color=${hex "green"}

    arch
    fps_limit_method=early
    toggle_fps_limit=Shift_L+F1
  '';
in
{
  options.programs.mangohud = {
    enable = lib.mkEnableOption "Catppuccin-themed MangoHud configuration" // {
      default = true;
    };
  };

  config = lib.mkIf (cfg.enable && features.gaming.enable) {
    xdg.configFile."MangoHud/MangoHud.conf".text = genMangoHudConfig;
  };
}
