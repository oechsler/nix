# Virtualisation Configuration
#
# Container management with Podman and optional VM management with QEMU/KVM.
#
# Configuration:
#   features.virtualisation.enable = true;             # Master switch (default: true)
#   features.virtualisation.container.enable = true;   # Enable Podman (default: true)
#   features.virtualisation.vm.enable = true;          # Enable QEMU/KVM (default: true)

{
  lib,
  config,
  ...
}:

let
  cfg = config.features.virtualisation;
in
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

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      # Podman with Docker-compatible CLI
      (lib.mkIf cfg.container.enable {
        virtualisation.podman = {
          enable = true;
          dockerCompat = true; # Enable Docker-compatible CLI
        };

        users.users.${config.user.name}.extraGroups = [ "podman" ];
      })

      # QEMU/KVM managed through libvirt and virt-manager
      (lib.mkIf cfg.vm.enable {
        virtualisation.libvirtd = {
          enable = true;
          qemu = {
            swtpm.enable = true;
          };
        };

        programs.virt-manager.enable = true;
        users.users.${config.user.name}.extraGroups = [ "libvirtd" ];
      })
    ]
  );
}
