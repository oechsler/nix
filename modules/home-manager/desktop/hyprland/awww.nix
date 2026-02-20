# Awww Configuration (Wayland Wallpaper Daemon)
#
# This module configures awww as the wallpaper manager for Hyprland.
#
# Features:
# - Per-monitor wallpaper support
# - Fade transition (1 second duration)
# - Automatic wallpaper reload on home-manager activation
# - Daemon-based (wallpaper persists across Hyprland restarts)
#
# How it works:
# 1. Start awww-daemon in background
# 2. Wait 2 seconds for daemon to be ready
# 3. Set wallpaper(s) via awww img command
# 4. Per-monitor: Set specific wallpaper for each monitor
# 5. Fallback: Set wallpaper on all monitors if no monitor config
#
# Scripts exposed:
#   config.awww.start - Start daemon and set wallpaper (used by hyprland.nix)

{ config, pkgs, inputs, lib, theme, displays, ... }:

let
  # Awww package from flake input
  awwwPkg = inputs.awww.packages.${pkgs.stdenv.hostPlatform.system}.default;

  # Generate wallpaper set commands
  # - Per-monitor: Set specific wallpaper for each monitor
  # - Fallback: Set wallpaper on all monitors
  wallpaperCommands =
    if displays.monitors == [] then
      # No monitor config: Set on all monitors
      "${awwwPkg}/bin/awww img ${theme.wallpaperPath} --transition-type fade --transition-duration 1"
    else
      # Per-monitor: Set specific wallpaper for each monitor
      lib.concatStringsSep "\n" (map (m:
        let wp = if m.wallpaper != null then m.wallpaper else theme.wallpaperPath;
        in "${awwwPkg}/bin/awww img ${wp} --outputs ${m.name} --transition-type fade --transition-duration 1"
      ) displays.monitors);

  # Start script: Launch daemon and set wallpaper
  startScript = pkgs.writeShellScript "awww-start" ''
    ${awwwPkg}/bin/awww-daemon &
    sleep 2  # Wait for daemon to be ready
    ${wallpaperCommands}
  '';

  # Set wallpaper script (without daemon start)
  setWallpaperScript = pkgs.writeShellScript "awww-set" wallpaperCommands;
in
{
  #===========================
  # Options
  #===========================

  options.awww = {
    start = lib.mkOption {
      type = lib.types.path;
      default = startScript;
      readOnly = true;
      description = "Script to start awww daemon and set wallpaper";
    };
  };

  #===========================
  # Configuration
  #===========================

  config = {
    # Install awww package
    home.packages = [ awwwPkg ];

    # Automatically reload wallpaper on home-manager activation
    # (e.g., after changing theme.wallpaper or monitor config)
    home.activation.setWallpaper = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      if ${pkgs.procps}/bin/pgrep -x "awww-daemon" > /dev/null 2>&1; then
        run ${setWallpaperScript}
      fi
    '';
  };
}
