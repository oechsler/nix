{ pkgs, lib, config, ... }:

let
  cfg = config.features.gaming;
in
{
  options.features.gaming = {
    enable = (lib.mkEnableOption "gaming support (Steam, Gamemode, Gamescope)") // { default = true; };
  };

  config = lib.mkIf cfg.enable {
    programs.steam.enable = true;
    programs.gamemode.enable = true;
    environment.systemPackages = [ pkgs.gamescope ];
  };
}
