{ config, pkgs, ... }:

{  
  environment.systemPackages = with pkgs; [
    dunst
    hyprpolkitagent
  ];

  xdg.portal = {
    enable = true;
    extraPortals = [
      pkgs.xdg-desktop-portal-hyprland
      pkgs.xdg-desktop-portal-gtk
    ];
  };

  programs.hyprland = {
    enable = true;
    withUWSM = true;
  };

  security.pam.services.sddm.enableGnomeKeyring = true;
  services.gnome.gnome-keyring.enable = true;

  services.gvfs.enable = true;
  services.udisks2.enable = true;
}
