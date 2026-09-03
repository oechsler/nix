# Awww Configuration (Wayland Wallpaper Daemon)
#
# This module configures awww as the wallpaper manager for Hyprland.
#
# Features:
# - Theme wallpaper from the shared backgrounds module
# - Fade transition (1 second duration)
# - Automatic wallpaper reload on home-manager activation
# - Parallel startup with the graphical session
# - Daemon-based (wallpaper persists across Hyprland restarts)

{
  pkgs,
  lib,
  theme,
  ...
}:

let
  awwwPkg = pkgs.awww;
  wallpaperCommands = "${awwwPkg}/bin/awww img ${theme.wallpaperPath} --transition-type fade --transition-duration 0.6";

  startScript = pkgs.writeShellScript "awww-start" ''
    set -eu

    ${awwwPkg}/bin/awww-daemon &
    daemon_pid=$!

    for _ in $(seq 1 20); do
      if ${awwwPkg}/bin/awww query > /dev/null 2>&1; then
        ${wallpaperCommands}
        wait "$daemon_pid"
        exit 0
      fi
      sleep 0.1
    done

    wait "$daemon_pid"
    exit 1
  '';

  setWallpaperScript = pkgs.writeShellScript "awww-set" ''
    set -eu

    export XDG_RUNTIME_DIR="''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
    wayland_socket=$(${pkgs.coreutils}/bin/ls -t "$XDG_RUNTIME_DIR"/wayland-* 2>/dev/null \
      | ${pkgs.gnugrep}/bin/grep -v '\.lock$' \
      | ${pkgs.gnugrep}/bin/grep -v '\-awww-daemon\.sock$' \
      | ${pkgs.coreutils}/bin/head -1 || true)
    [ -n "$wayland_socket" ] || exit 0
    export WAYLAND_DISPLAY=$(${pkgs.uutils-coreutils-noprefix}/bin/basename "$wayland_socket")
    ${wallpaperCommands}
  '';
in
{
  #===========================
  # Configuration
  #===========================

  config = {
    home.packages = [ awwwPkg ];

    systemd.user = {
      services = {
        awww = {
          Unit = {
            Description = "Awww wallpaper daemon";
            After = [ "graphical-session.target" ];
            PartOf = [ "graphical-session.target" ];
            ConditionEnvironment = "WAYLAND_DISPLAY";
          };
          Service = {
            ExecStart = startScript;
            Restart = "on-failure";
            RestartSec = 2;
          };
          Install.WantedBy = [ "graphical-session.target" ];
        };

        awww-reload = {
          Unit.Description = "Reload wallpaper on background change";
          Service = {
            Type = "oneshot";
            ExecStart = setWallpaperScript;
          };
        };
      };

      paths.awww-reload = {
        Unit.Description = "Watch for wallpaper changes";
        Install.WantedBy = [ "graphical-session.target" ];
        Path.PathChanged = [ "/var/lib/backgrounds/.reload" ];
      };
    };

    home.activation.setWallpaper = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      if ${pkgs.procps}/bin/pgrep -x "awww-daemon" > /dev/null 2>&1; then
        run ${setWallpaperScript}
      fi
    '';
  };
}
