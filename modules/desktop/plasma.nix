{ config, pkgs, ... }:

{
  # X11
  services.xserver.enable = true;
  services.xserver.xkb = {
    layout = "de";
    variant = "";
  };
  
  # Plasma
  services.displayManager.sddm.enable = true;
  services.desktopManager.plasma6.enable = true;
}
