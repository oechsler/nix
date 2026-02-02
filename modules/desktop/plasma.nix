{ config, pkgs, ... }:

let
  wallpaper = ../../backgrounds/Cloudsnight.jpg;

  blurredWallpaper = pkgs.runCommand "blurred-wallpaper.jpg" {
    buildInputs = [ pkgs.imagemagick ];
  } ''
    convert ${wallpaper} -blur 0x30 $out
  '';
in
{
  # Keyboard Layout
  services.xserver.xkb = {
    layout = "de";
    variant = "";
  };
  
  services.displayManager.sddm = {
    enable = true;
    wayland.enable = true;
  };

  catppuccin.sddm = {
    enable = true;
    background = blurredWallpaper;
    loginBackground = true;
  };
  
  services.desktopManager.plasma6.enable = true;
}
