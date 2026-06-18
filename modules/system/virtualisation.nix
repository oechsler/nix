# Virtualisation Configuration
#
# Docker container runtime with IPv6 fixups for desktop hosts.
#
# Configuration:
#   features.virtualisation.enable = true;  # Enable Docker (default: true)

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
       # Podman (replaces Docker with full compatibility)
       {
         virtualisation.podman = {
           enable = true;
           dockerCompat = true; # Enable Docker-compatible CLI
         };

         users.users.${config.user.name}.extraGroups = [ "podman" ];
       }
     ]
   );
}
