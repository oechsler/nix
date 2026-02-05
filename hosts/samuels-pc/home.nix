{ user, features, lib, ... }:

{
  imports = [
    ../../modules/home-manager
  ];

  home.username = user.name;
  home.homeDirectory = "/home/${user.name}";
  home.stateVersion = "25.11";

  programs.home-manager.enable = true;
  nixpkgs.config.allowUnfree = true;

  # Longer idle timeouts for desktop PC
  idle.timeouts = {
    dimBattery = 300;
    dimAcLockBattery = 600;
    suspendBattery = 600;
    lockSuspendAc = 3600;
  };
}
