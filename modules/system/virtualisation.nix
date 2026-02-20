# Virtualisation Configuration
#
# This module enables Docker container support.
#
# Configuration:
#   features.virtualisation.enable = true;  # Enable Docker (default: true)
#
# Features:
# - Docker daemon starts on boot
# - User added to docker group (run containers without sudo)
#
# Usage:
#   docker run hello-world
#   docker-compose up

{ lib, config, ... }:

let
  cfg = config.features.virtualisation;
in
{
  options.features.virtualisation = {
    enable = (lib.mkEnableOption "virtualisation support (Docker)") // { default = true; };
  };

  config = lib.mkIf cfg.enable {
    virtualisation.docker = {
      enable = true;
      enableOnBoot = true;
    };

    users.users.${config.user.name}.extraGroups = [ "docker" ];
  };
}
