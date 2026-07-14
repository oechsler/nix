# Auto-generated Hardware Configuration Placeholder (samuels-ser9)
#
# Replace this file on the SER9 with:
#   nixos-generate-config --show-hardware-config > hardware-configuration.generated.nix
#
# Disk-related options are stripped by hardware-configuration.nix because disko
# and luks.nix manage filesystems and encrypted devices.

{ modulesPath, ... }:

{
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
  ];

  boot.initrd.availableKernelModules = [
    "nvme"
    "xhci_pci"
    "usb_storage"
    "sd_mod"
  ];
  boot.initrd.kernelModules = [ ];
  boot.kernelModules = [ "kvm-amd" ];
  boot.extraModulePackages = [ ];

  nixpkgs.hostPlatform = "x86_64-linux";
}
