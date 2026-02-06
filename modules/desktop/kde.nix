{ config, pkgs, lib, ... }:

{
  config = lib.mkIf (config.features.desktop.enable && config.features.desktop.wm == "kde") {
    services.desktopManager.plasma6.enable = true;

    xdg.portal = {
      enable = true;
      extraPortals = [
        pkgs.kdePackages.xdg-desktop-portal-kde
      ];
    };

    environment.systemPackages = with pkgs.kdePackages; [
      partitionmanager
      plasma-browser-integration
    ];

    services.gvfs.enable = true;
    services.udisks2.enable = true;
  };
}
