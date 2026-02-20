# Hardware Configuration Wrapper (samuels-pc)
#
# This module imports the auto-generated hardware config and removes disk-related
# options that are managed by disko.nix instead.
#
# Why:
# - nixos-generate-config creates hardware-configuration.nix with fileSystems, swap, LUKS
# - We use disko.nix for declarative disk management instead
# - This wrapper imports the generated config but strips disk options
#
# Regenerate auto-detected hardware config:
#   nixos-generate-config --show-hardware-config > hardware-configuration.generated.nix
#
# What gets stripped:
# - fileSystems (managed by disko.nix)
# - swapDevices (managed by disko.nix)
# - boot.initrd.luks (managed by luks.nix)
#
# What gets kept:
# - CPU/GPU drivers
# - Kernel modules
# - Boot loader config
# - Firmware settings

{ config, lib, pkgs, modulesPath, ... }:

let
  generated = import ./hardware-configuration.generated.nix { inherit config lib pkgs modulesPath; };
  cleaned = builtins.removeAttrs generated [ "fileSystems" "swapDevices" ];
  # Strip boot.initrd.luks if present (disko handles LUKS devices)
  hasLuks = cleaned ? boot && cleaned.boot ? initrd && cleaned.boot.initrd ? luks;
  withoutLuks =
    if hasLuks then
      cleaned // {
        boot = cleaned.boot // {
          initrd = builtins.removeAttrs cleaned.boot.initrd [ "luks" ];
        };
      }
    else
      cleaned;
in
  withoutLuks
