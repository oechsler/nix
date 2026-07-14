# Display Helpers
#
# Shared helpers for values derived from displays.monitors.

{ lib }:

{
  hasHDR = monitors: lib.any (monitor: monitor.hdr != 0) monitors;

  hasDesktopHDR = monitors: lib.any (monitor: monitor.hdr == 2) monitors;

  hasVRR = monitors: lib.any (monitor: monitor.vrr != 0) monitors;

  primaryName = monitors: if monitors != [ ] then (lib.head monitors).name else "";

  primaryScale = fallback: monitors: if monitors != [ ] then (lib.head monitors).scale else fallback;

  monitorWallpaper =
    theme: monitor: if monitor.wallpaper != null then monitor.wallpaper else theme.wallpaperPath;
}
