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
