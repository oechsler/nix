# samuels-razer Home Manager Configuration
#
# User-level configuration for samuels-razer (laptop).
#
# Uses default idle timeouts from common/idle.nix:
# - Optimized for battery usage
# - Faster dim/lock/suspend than desktop
#
# See samuels-pc/home.nix for comparison with desktop timeouts.

{ user, ... }:

{
  imports = [
    ../../modules/home-manager
  ];

  home.username = user.name;
  home.homeDirectory = "/home/${user.name}";
  home.stateVersion = "25.11";

  programs.home-manager.enable = true;
}
