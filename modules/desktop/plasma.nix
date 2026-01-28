{ config, pkgs, ... }:

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
  
  services.desktopManager.plasma6.enable = true;
}
