# KDE Plasma Desktop Environment (System-level)
#
# This module enables KDE Plasma 6 desktop at the system level.
# User-level KDE configuration is in home-manager/desktop/kde/
#
# Installed:
# - KDE Plasma 6 desktop environment
# - XDG Desktop Portal (KDE for file dialogs, screenshots)
# - KDE Partition Manager
# - Plasma Browser Integration
#
# Services:
# - GVFS for virtual filesystems (trash, network shares)
# - udisks2 for automatic disk mounting
#
# Active when:
#   features.desktop.enable = true
#   features.desktop.wm = "kde"

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
