# KScreen Helpers
#
# Shared helpers for generating kscreen-doctor arguments from displays.monitors.

{ lib }:

let
  rotation =
    rot:
    {
      "normal" = "normal";
      "90" = "right";
      "180" = "inverted";
      "270" = "left";
    }
    .${rot};

  vrrPolicy =
    vrr:
    {
      "0" = "never";
      "1" = "always";
      "2" = "automatic";
    }
    .${toString vrr};
in
{
  inherit rotation vrrPolicy;

  monitorArgs =
    monitors:
    lib.concatMapStringsSep " " (
      m:
      lib.concatStringsSep " " (
        [
          "output.${m.name}.scale.${toString m.scale}"
          "output.${m.name}.mode.${toString m.width}x${toString m.height}@${toString m.refreshRate}"
          "output.${m.name}.position.${toString m.x},${toString m.y}"
          "output.${m.name}.rotation.${rotation m.rotation}"
          "output.${m.name}.vrrpolicy.${vrrPolicy m.vrr}"
        ]
        ++ lib.optionals m.hdr [
          "output.${m.name}.hdr.enable"
          "output.${m.name}.sdr-brightness.${toString m.hdrSdrMaxLuminance}"
        ]
      )
    ) monitors;
}
