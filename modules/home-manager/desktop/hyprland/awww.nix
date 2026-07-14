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
# 4. Set default wallpaper on all monitors
# 5. Per-monitor: Override wallpaper for explicitly configured monitors
#
# Scripts exposed:
#   config.awww.start - Start daemon and set wallpaper (used by hyprland.nix)

{
  config,
  pkgs,
  lib,
  theme,
  displays,
  ...
}:

let
  awwwPkg = pkgs.awww;
  displayHelpers = import ../../../lib/displays.nix { inherit lib; };

  # Generate wallpaper set commands.
  # Set the default wallpaper on all outputs first so unknown monitors are covered,
  # then override explicitly configured monitors with their per-monitor wallpaper.
  wallpaperCommands = lib.concatStringsSep "\n" (
    [
      "${awwwPkg}/bin/awww img ${theme.wallpaperPath} --transition-type fade --transition-duration 1"
    ]
    ++ lib.optionals (displays.monitors != [ ]) (
      map (
        m:
        let
          wp = displayHelpers.monitorWallpaper theme m;
        in
        "${awwwPkg}/bin/awww img ${wp} --outputs ${m.name} --transition-type fade --transition-duration 1"
      ) displays.monitors
    )
  );

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
    #
    # Why explicit env vars: home-manager-samuel.service runs without WAYLAND_DISPLAY,
    # so awww can't connect to the compositor unless we set it manually.
    home.activation.setWallpaper = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      if ${pkgs.procps}/bin/pgrep -x "awww-daemon" > /dev/null 2>&1; then
        export XDG_RUNTIME_DIR="''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"

        WAYLAND_SOCKET=$(ls -t "$XDG_RUNTIME_DIR"/wayland-* 2>/dev/null | grep -v '\.lock$' | grep -v '\-awww-daemon\.sock$' | head -1)
        if [ -n "$WAYLAND_SOCKET" ]; then
          export WAYLAND_DISPLAY=$(${pkgs.coreutils}/bin/basename "$WAYLAND_SOCKET")
        else
          export WAYLAND_DISPLAY="wayland-1"
        fi

        run ${setWallpaperScript}
      fi
    '';

    # Path unit: reload wallpaper whenever the extraction service signals a change
    systemd.user.services.awww-reload = {
      Unit.Description = "Reload wallpaper on background change";
      Service = {
        Type = "oneshot";
        ExecStart = setWallpaperScript;
        Environment = [
          "XDG_RUNTIME_DIR=%t"
          "WAYLAND_DISPLAY=wayland-1"
        ];
      };
    };
    systemd.user.paths.awww-reload = {
      Unit.Description = "Watch for wallpaper changes";
      Install.WantedBy = [ "graphical-session.target" ];
      Path.PathChanged = [ "/var/lib/backgrounds/.reload" ];
    };
  };
}
