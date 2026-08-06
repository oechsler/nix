# Awww Configuration (Wayland Wallpaper Daemon)
#
# This module configures awww as the wallpaper manager for Hyprland.
#
# Features:
# - Per-monitor wallpaper support
# - Fade transition (1 second duration)
# - Automatic wallpaper reload on home-manager activation
# - Parallel startup with the graphical session
# - Daemon-based (wallpaper persists across Hyprland restarts)

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
      "${awwwPkg}/bin/awww img ${theme.wallpaperPath} --transition-type fade --transition-duration 0.6"
    ]
    ++ lib.optionals (displays.monitors != [ ]) (
      map (
        m:
        let
          wp = displayHelpers.monitorWallpaper theme m;
        in
        "${awwwPkg}/bin/awww img ${wp} --outputs ${m.name} --transition-type fade --transition-duration 0.6"
      ) displays.monitors
    )
  );

  startScript = pkgs.writeShellScript "awww-start" ''
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

  setWallpaperScript = pkgs.writeShellScript "awww-set" wallpaperCommands;
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
            Environment = [
              "XDG_RUNTIME_DIR=%t"
              "WAYLAND_DISPLAY=wayland-1"
            ];
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
        export XDG_RUNTIME_DIR="''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"

        WAYLAND_SOCKET=$(ls -t "$XDG_RUNTIME_DIR"/wayland-* 2>/dev/null | grep -v '\.lock$' | grep -v '\-awww-daemon\.sock$' | head -1)
        if [ -n "$WAYLAND_SOCKET" ]; then
          export WAYLAND_DISPLAY=$(${pkgs.uutils-coreutils-noprefix}/bin/basename "$WAYLAND_SOCKET")
        else
          export WAYLAND_DISPLAY="wayland-1"
        fi

        run ${setWallpaperScript}
      fi
    '';
  };
}
