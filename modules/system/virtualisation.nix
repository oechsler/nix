# Virtualisation Configuration
#
# This module enables virtualisation and containerisation support.
#
# Configuration:
#   features.virtualisation.enable = true;          # Enable Docker (default: true)
#   features.virtualisation.waydroid.enable = true; # Android container (requires virtualisation.enable)
#
# Docker:
# - Docker daemon starts on boot
# - User added to docker group (run containers without sudo)
#
# Waydroid:
# - Android container runtime for Wayland
# - Runs Android apps natively on Linux
# - Requires Wayland (KDE/Hyprland)
#
# Usage:
#   docker run hello-world
#   waydroid show-full-ui  # Launch Android UI

{
  lib,
  config,
  pkgs,
  ...
}:

let
  cfg = config.features.virtualisation;
  disableDockerInterfaceIPv6 = pkgs.writeShellScript "disable-docker-interface-ipv6" ''
    iface=''${1:-}

    case "$iface" in
      docker0|br-*|veth*) ;;
      *) exit 0 ;;
    esac

    sysctl_path="/proc/sys/net/ipv6/conf/$iface/disable_ipv6"
    if [ -w "$sysctl_path" ]; then
      printf '1' > "$sysctl_path"
    fi
  '';
in
{
  options.features.virtualisation = {
    enable = (lib.mkEnableOption "virtualisation support (Docker)") // {
      default = true;
    };
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      # Docker
      {
        virtualisation.docker = {
          enable = true;
          enableOnBoot = true;
        };

        users.users.${config.user.name}.extraGroups = [ "docker" ];
      }

      # Desktop Docker is used for local development. Keep host IPv6 enabled, but
      # avoid IPv6 link-local route churn on Docker bridge/veth interfaces.
      (lib.mkIf config.features.desktop.enable {
        virtualisation.docker.daemon.settings = {
          ipv6 = false;
          ip6tables = false;
        };

        services.udev.extraRules = ''
          ACTION=="add", SUBSYSTEM=="net", KERNEL=="docker0|br-*|veth*", RUN+="${disableDockerInterfaceIPv6} %k"
        '';

        systemd.services.disable-docker-interface-ipv6 = {
          description = "Disable IPv6 on Docker bridge and veth interfaces";
          wantedBy = [ "multi-user.target" ];
          after = [ "docker.service" ];
          serviceConfig.Type = "oneshot";
          script = ''
            for path in /proc/sys/net/ipv6/conf/docker0/disable_ipv6 /proc/sys/net/ipv6/conf/br-*/disable_ipv6 /proc/sys/net/ipv6/conf/veth*/disable_ipv6; do
              [ -e "$path" ] || continue
              printf '1' > "$path"
            done
          '';
        };
      })
    ]
  );
}
