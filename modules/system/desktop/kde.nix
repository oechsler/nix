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
    services = {
      desktopManager.plasma6.enable = true;
      gvfs.enable = true;
      udisks2.enable = true;
    };

    # Pass the SDDM login password (local or LDAP) to KDE Wallet.
    security.pam.services.sddm.kwallet.enable = true;

    # KDE's systemd app scopes currently SIGKILL Mumble shortly after launch.
    # Keep desktop applications in the regular user session instead.
    environment.sessionVariables.KDE_APPLICATIONS_AS_SCOPE = "0";

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
