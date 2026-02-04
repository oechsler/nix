{ config, pkgs, ... }:

{
  services.gnome-keyring = {
    enable = true;
    components = [ "secrets" ];
  };

  home.packages = with pkgs; [
    alsa-scarlett-gui
    bitwarden-desktop
    discord
    freecad
    gnome-disk-utility
    libreoffice
    loupe
    nextcloud-client
    obsidian
    pika-backup
    prusa-slicer
    spotify
    trayscale
  ];
}
