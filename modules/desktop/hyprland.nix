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
