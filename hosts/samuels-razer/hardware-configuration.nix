# Wrapper that imports the generated config and strips disk-related options
# (disko.nix handles fileSystems, swapDevices, and LUKS). Regenerate with:
#   nixos-generate-config --show-hardware-config > hardware-configuration.generated.nix
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
