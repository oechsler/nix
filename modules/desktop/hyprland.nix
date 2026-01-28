{ config, pkgs, ... }:

{  
  environment.systemPackages = with pkgs; [
    dunst
    hyprpolkitagent
  ];

  xdg.portal = {
    enable = true;
    extraPortals = [ pkgs.xdg-desktop-portal-hyprland ];
  };

  programs.hyprland = {
    enable = true;
    withUWSM = true;
  };
}
