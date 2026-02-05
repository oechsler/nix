# Wrapper that imports the generated config and strips fileSystems/swapDevices
# (disko.nix handles mounts). Regenerate with:
#   nixos-generate-config --root /mnt --show-hardware-config > hardware-configuration.generated.nix
{ config, lib, pkgs, modulesPath, ... }:

let
  generated = import ./hardware-configuration.generated.nix { inherit config lib pkgs modulesPath; };
in
  builtins.removeAttrs generated [ "fileSystems" "swapDevices" ]
