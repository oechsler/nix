{ user, ... }:

{
  imports = [
    ../../modules/home-manager/desktop/hyprland.nix
    ../../modules/home-manager/desktop/theme.nix
    ../../modules/home-manager/programs
  ];

  home.username = user.name;
  home.homeDirectory = "/home/${user.name}";
  home.stateVersion = "25.11";

  programs.home-manager.enable = true;
  nixpkgs.config.allowUnfree = true;

  hyprland.startupApps = [
    "bitwarden"
    "nextcloud --background"
    "discord --start-minimized"
    "steam -silent"
    "jetbrains-toolbox --minimize"
    "sleep 3 && trayscale --hide-window"
  ];

  hypridle.timeouts = {
    dimBattery = 120;
    dimAcLockBattery = 300;
    suspendBattery = 300;
    lockSuspendAc = 1800;
  };
}
