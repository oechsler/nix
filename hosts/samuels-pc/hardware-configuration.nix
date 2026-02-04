# Hardware configuration (kernel modules, CPU, GPU)
# Filesystem mounts are handled by disko.nix
{ config, lib, pkgs, modulesPath, ... }:

{
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
  ];

  # Kernel modules for NVMe and common hardware
  boot.initrd.availableKernelModules = [
    "nvme"
    "xhci_pci"
    "ahci"
    "usbhid"
    "sd_mod"
  ];
  boot.kernelModules = [ "kvm-intel" ];  # or kvm-amd for AMD CPUs

  # CPU microcode (uncomment appropriate line after install)
  # hardware.cpu.intel.updateMicrocode = true;
  # hardware.cpu.amd.updateMicrocode = true;

  # GPU (uncomment after identifying hardware)
  # hardware.nvidia.open = true;
  # services.xserver.videoDrivers = [ "nvidia" ];
  # hardware.graphics.enable = true;
}
