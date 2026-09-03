# Container and virtual machine feature options.

{ lib, ... }:

{
  options.features.virtualisation = {
    enable = (lib.mkEnableOption "container and virtualisation support") // {
      default = true;
    };
    container.enable = (lib.mkEnableOption "container support") // {
      default = true;
    };
    vm.enable = (lib.mkEnableOption "QEMU/KVM virtual machines") // {
      default = true;
    };
  };
}
