# Virtualisation Configuration
#
# This module enables virtualisation and containerisation support.
#
# Configuration:
#   features.virtualisation.enable = true;          # Enable Docker (default: true)
#   features.virtualisation.waydroid.enable = true; # Android container (default: false)
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

{ lib, config, ... }:

let
  cfg = config.features.virtualisation;
in
{
  options.features.virtualisation = {
    enable = (lib.mkEnableOption "virtualisation support (Docker)") // { default = true; };
    waydroid = {
      enable = lib.mkEnableOption "Waydroid (Android container)";
    };
  };

  config = lib.mkMerge [
    # Docker
    (lib.mkIf cfg.enable {
      virtualisation.docker = {
        enable = true;
        enableOnBoot = true;
      };

      users.users.${config.user.name}.extraGroups = [ "docker" ];
    })

    # Waydroid
    (lib.mkIf cfg.waydroid.enable {
      virtualisation.waydroid.enable = true;
    })
  ];
}
