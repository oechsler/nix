# Display Helpers
#
# Shared helpers for values derived from displays.monitors.

{ lib }:

{
  hasHDR = monitors: lib.any (monitor: monitor.hdr != 0) monitors;

  hasDesktopHDR = monitors: lib.any (monitor: monitor.hdr == 2) monitors;

  hasVRR = monitors: lib.any (monitor: monitor.vrr != 0) monitors;

  primaryName = monitors: lib.optionalString (monitors != [ ]) (lib.head monitors).name;

  primaryScale = fallback: monitors: (lib.head (monitors ++ [ { scale = fallback; } ])).scale;
}
