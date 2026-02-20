# Gaming Configuration
#
# This module enables gaming support with Steam and performance tools.
#
# Configuration:
#   features.gaming.enable = true;  # Enable gaming support (default: true)
#
# Installed:
# - Steam - Gaming platform with Proton (Windows game compatibility)
# - Gamemode - Automatic performance optimizations for games
# - Gamescope - Wayland compositor for gaming (frame limiting, upscaling)
#
# Features:
# - Proton/Wine for Windows games
# - Gamemode optimizes CPU governor, I/O priority when games run
# - Gamescope provides FPS limiting, HDR, resolution scaling

{ pkgs, lib, config, ... }:

let
  cfg = config.features.gaming;
in
{
  options.features.gaming = {
    enable = (lib.mkEnableOption "gaming support (Steam, Gamemode, Gamescope)") // { default = true; };
  };

  config = lib.mkIf cfg.enable {
    programs.steam.enable = true;
    programs.gamemode.enable = true;
    environment.systemPackages = [ pkgs.gamescope ];
  };
}
