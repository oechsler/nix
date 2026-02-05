# Placeholder - will be replaced by install.sh during installation
{ config, lib, pkgs, modulesPath, ... }:

{
  imports = [ (modulesPath + "/installer/scan/not-detected.nix") ];

  boot.initrd.availableKernelModules = [ "nvme" "xhci_pci" "ahci" "usbhid" "sd_mod" ];
  boot.kernelModules = [ ];

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
}
