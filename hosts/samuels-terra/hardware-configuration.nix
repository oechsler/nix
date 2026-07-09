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
# - boot.initrd.luks (managed by luks.nix)
#
# What gets kept:
# - CPU/GPU drivers
# - Kernel modules
# - Boot loader config
# - Firmware settings
#
# Manual overrides (hardware not detected by nixos-generate-config):
# - ucsi_acpi, typec_ucsi: USB-C controller modules for FIDO2 key detection at boot
# - mt7925e: MediaTek MT7925 WiFi 7 + Bluetooth 5.4 (ROG Strix X870-I onboard adapter)

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
  # Strip boot.initrd.luks if present (disko handles LUKS devices)
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
    # MediaTek MT7925 WiFi 7 + Bluetooth 5.4 — not auto-detected, must be loaded explicitly
    kernelModules =
      ((withoutLuks.boot or { }).kernelModules or [ ]) ++ [ "mt7925e" ];

    initrd = ((withoutLuks.boot or { }).initrd or { }) // {
      # USB-C controller modules required in initrd for FIDO2 key detection at boot
      availableKernelModules =
        ((withoutLuks.boot or { }).initrd or { }).availableKernelModules or [ ]
        ++ [
          "ucsi_acpi"
          "typec_ucsi"
        ];
    };
  };
}
