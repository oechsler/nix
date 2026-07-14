# Hardware Configuration Wrapper (samuels-ser9)
#
# This module imports the auto-generated hardware config and removes disk-related
# options that are managed by disko.nix instead.
#
# Regenerate auto-detected hardware config on the SER9:
#   nixos-generate-config --show-hardware-config > hardware-configuration.generated.nix
#
# What gets stripped:
# - fileSystems (managed by disko.nix)
# - swapDevices (managed by disko.nix)
# - boot.initrd.luks (managed by luks.nix)

{
  config,
  lib,
  pkgs,
  modulesPath,
  ...
}:

let
  generated = import ./hardware-configuration.generated.nix {
    inherit
      config
      lib
      pkgs
      modulesPath
      ;
  };
  cleaned = builtins.removeAttrs generated [
    "fileSystems"
    "swapDevices"
  ];
  hasLuks = cleaned ? boot && cleaned.boot ? initrd && cleaned.boot.initrd ? luks;
  withoutLuks =
    if hasLuks then
      cleaned
      // {
        boot = cleaned.boot // {
          initrd = builtins.removeAttrs cleaned.boot.initrd [ "luks" ];
        };
      }
    else
      cleaned;
in
withoutLuks
