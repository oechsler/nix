# Hardware Configuration Wrapper (samuels-terra)
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
# - boot.initrd.luks (derived from disko.nix)
#
# What gets kept:
# - CPU/GPU drivers
# - Kernel modules
# - Boot loader config
# - Firmware settings
#
# Manual override (hardware not detected by nixos-generate-config):
# - ucsi_acpi, typec_ucsi: USB-C controller in initrd.kernelModules (not availableKernelModules)
#   so they are loaded immediately at initrd start — before LUKS FIDO2 unlock prompt

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
  # Strip generated boot.initrd.luks; the shared Disko module derives it.
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
// {
  boot = (withoutLuks.boot or { }) // {
    initrd = ((withoutLuks.boot or { }).initrd or { }) // {
      # Force-load USB-C controller modules at initrd start so the YubiKey
      # is visible before systemd-cryptsetup asks for FIDO2 touch.
      # availableKernelModules = load-on-demand (too late for LUKS unlock).
      # kernelModules = load immediately (required here).
      kernelModules = ((withoutLuks.boot or { }).initrd or { }).kernelModules or [ ] ++ [
        "ucsi_acpi"
        "typec_ucsi"
      ];
    };
  };
}
