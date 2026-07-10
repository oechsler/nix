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
# - ucsi_acpi, typec_ucsi: USB-C controller in initrd.kernelModules (not availableKernelModules)
#   so they are loaded immediately at initrd start — before LUKS FIDO2 unlock prompt
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
    # MediaTek MT7927 (Filogic 380) WiFi 7 + BT 5.4 — PCI ID 14c3:7927.
    # MT7927 support was merged upstream on 2026-06-09 (Linux 7.2+).
    # mt7925e is the correct module (MT7927 shares the driver); the PCI ID
    # 14c3:7927 will be recognised once CachyOS ships a kernel >= that commit.
    # Until then WiFi/BT are non-functional — update flake when 7.2 is available.
    kernelModules =
      ((withoutLuks.boot or { }).kernelModules or [ ]) ++ [ "mt7925e" ];

    initrd = ((withoutLuks.boot or { }).initrd or { }) // {
      # Force-load USB-C controller modules at initrd start so the YubiKey
      # is visible before systemd-cryptsetup asks for FIDO2 touch.
      # availableKernelModules = load-on-demand (too late for LUKS unlock).
      # kernelModules = load immediately (required here).
      kernelModules =
        ((withoutLuks.boot or { }).initrd or { }).kernelModules or [ ]
        ++ [
          "ucsi_acpi"
          "typec_ucsi"
        ];
    };
  };
}
