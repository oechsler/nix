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
  pkgs,
  config,
  ...
}:

let
  cfg = config.features.virtualisation;
  defaultNetworkXml = pkgs.writeText "libvirt-default-network.xml" ''
    <network>
      <name>default</name>
      <forward mode='nat'>
        <nat ipv6='yes'/>
      </forward>
      <bridge name='virbr0' stp='on' delay='0'/>
      <ip address='192.168.122.1' netmask='255.255.255.0'>
        <dhcp>
          <range start='192.168.122.2' end='192.168.122.254'/>
        </dhcp>
      </ip>
      <ip family='ipv6' address='fd42:122:122::1' prefix='64'>
        <dhcp>
          <range start='fd42:122:122::2' end='fd42:122:122::ffff'/>
        </dhcp>
      </ip>
    </network>
  '';
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

        systemd.services.libvirt-default-network = {
          description = "Ensure the libvirt default network is available";
          wantedBy = [ "multi-user.target" ];
          wants = [ "network-online.target" ];
          after = [ "libvirtd.service" "network-online.target" ];
          requires = [ "libvirtd.service" ];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            ExecStart = pkgs.writeShellScript "libvirt-default-network" ''
              if ! ${pkgs.libvirt}/bin/virsh -c qemu:///system net-info default >/dev/null 2>&1; then
                ${pkgs.libvirt}/bin/virsh -c qemu:///system net-define ${defaultNetworkXml}
              fi

              ${pkgs.libvirt}/bin/virsh -c qemu:///system net-autostart default
              if ! ${pkgs.libvirt}/bin/virsh -c qemu:///system net-info default | ${pkgs.gnugrep}/bin/grep -q 'Active:.*yes'; then
                ${pkgs.libvirt}/bin/virsh -c qemu:///system net-start default
              fi
            '';
          };
        };

        # virt-manager is launched through a Nix wrapper. Keep its wrapper
        # class for window matching, but use the packaged icon directly.
        home-manager.users.${config.user.name}.xdg.desktopEntries.virt-manager = {
          name = "Virtual Machine Manager";
          genericName = "Virtual machine viewer/manager";
          comment = "Manage virtual machines";
          exec = "virt-manager";
          icon = "virt-manager";
          terminal = false;
          categories = [
            "System"
            "Emulator"
            "GTK"
          ];
          settings.StartupWMClass = ".virt-manager-wrapped";
        };
      })
    ]
  );
}
