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
