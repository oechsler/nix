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

{
  config,
  pkgs,
  lib,
  ...
}:

{
  config = lib.mkIf (config.features.desktop.enable && config.features.desktop.wm == "kde") {
    features.desktop.kde.tray = {
      shown = lib.mkDefault (
        [ "Mumble" ]
        ++ lib.optional config.features.apps.nextcloud.enable "Nextcloud"
        ++ [
          "Proton Pass_status_icon_1"
          "dev.deedles.Trayscale"
          "vesktop_status_icon_1"
          "org.kde.plasma.bluetooth"
          "org.kde.plasma.battery"
          "org.kde.plasma.volume"
          "org.kde.plasma.networkmanagement"
        ]
      );
      hidden = lib.mkDefault [
        "org.kde.kscreen"
        "org.kde.plasma.devicenotifier"
        "org.kde.plasma.brightness"
        "org.kde.plasma.mediacontroller"
        "org.kde.plasma.clipboard"
      ];
    };
    features.desktop.kde.favorites.entries = lib.mkDefault [
      config.features.desktop.browser.type
      (if config.features.desktop.fileManager == "terminal" then "yazi" else "org.kde.dolphin")
      "kitty"
      "systemsettings"
    ];

    services = {
      desktopManager.plasma6.enable = true;
      gvfs.enable = true;
      udisks2.enable = true;
    };

    # Pass the SDDM login password (local or LDAP) to KDE Wallet.
    security.pam.services.sddm.kwallet.enable = true;

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
  };
}
