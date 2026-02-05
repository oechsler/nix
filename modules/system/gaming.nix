{ pkgs, lib, config, ... }:

let
  cfg = config.features.gaming;
in
{
  options.features.gaming = {
    enable = (lib.mkEnableOption "gaming support (Steam, Gamemode, Gamescope)") // { default = true; };
    gamescope.session = {
      enable = lib.mkEnableOption "Gamescope session (Steam Deck mode for SDDM)";
      autoLogin = lib.mkEnableOption "auto-login into Gamescope session";
    };
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    {
      programs.steam.enable = true;
      programs.gamemode.enable = true;
      environment.systemPackages = [ pkgs.gamescope ];
    }

    (lib.mkIf cfg.gamescope.session.enable {
      programs.steam.gamescopeSession.enable = true;
    })

    (lib.mkIf (cfg.gamescope.session.enable && cfg.gamescope.session.autoLogin) {
      services.displayManager.autoLogin = {
        enable = true;
        user = config.user.name;
      };
      services.displayManager.defaultSession = "gamescope-wayland";
    })
  ]);
}
