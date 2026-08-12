# Virtualisation Configuration
#
# Container and VM management with Docker and libvirt.
# Docker gets IPv6 fixups on desktop hosts.
#
# Configuration:
#   features.virtualisation.enable = true;  # Enable Docker (default: true)

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
