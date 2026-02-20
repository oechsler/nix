# Hyprland Desktop Environment (System-level)
#
# This module enables Hyprland window manager at the system level.
# User-level Hyprland configuration is in home-manager/desktop/hyprland/
#
# Installed:
# - Hyprland with UWSM (Universal Wayland Session Manager)
# - XDG Desktop Portals (Hyprland + GTK for file dialogs, screenshots)
# - Dunst notification daemon
# - GParted partition manager (themed)
# - Hyprpolkitagent for authentication dialogs
#
# Services:
# - GNOME Keyring for secret storage (passwords, SSH keys)
# - GVFS for virtual filesystems (trash, network shares)
# - udisks2 for automatic disk mounting
#
# Active when:
#   features.desktop.enable = true
#   features.desktop.wm = "hyprland"

{ config, pkgs, lib, ... }:

{
  config = lib.mkIf (config.features.desktop.enable && config.features.desktop.wm == "hyprland") {
    environment.systemPackages = with pkgs; [
      dunst
      (gparted.overrideAttrs (old: {
        postFixup = (old.postFixup or "") + ''
          wrapProgram $out/libexec/gpartedbin \
            --set GTK_THEME "${if config.theme.catppuccin.flavor == "latte" then "Adwaita" else "Adwaita:dark"}"
        '';
      }))
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
  };
}
