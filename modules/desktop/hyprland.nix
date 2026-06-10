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
# Autologin keyring unlock:
#   When features.desktop.login = "autologin", SDDM uses a separate PAM
#   service (sddm-autologin) that does NOT run the normal sddm auth stack.
#   This module adds pam_systemd_loadkey + pam_gnome_keyring to that stack,
#   plus KeyringMode=inherit on the display-manager service, so the keyring
#   can be unlocked from a LUKS passphrase cached during boot. This only
#   works with features.encryption.unlockMethod = "password".
#
# Active when:
#   features.desktop.enable = true
#   features.desktop.wm = "hyprland"

{
  config,
  pkgs,
  lib,
  ...
}:

{
  config = lib.mkIf (config.features.desktop.enable && config.features.desktop.wm == "hyprland") {
    environment.systemPackages = with pkgs; [
      dunst
      (gparted.overrideAttrs (old: {
        postFixup = (old.postFixup or "") + ''
          wrapProgram $out/libexec/gpartedbin \
            --set GTK_THEME "${
              if config.theme.catppuccin.flavor == "latte" then "Adwaita" else "Adwaita:dark"
            }"
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
      # Hyprland portal handles screen/input; GTK portal handles Settings
      # (color-scheme for WebKitGTK/Tauri apps like CoolerControl)
      config.hyprland = {
        default = [
          "hyprland"
          "gtk"
        ];
      };
    };

    programs.hyprland = {
      enable = true;
      withUWSM = true;
    };

    security.pam.services.sddm.enableGnomeKeyring = true;

    # SDDM autologin uses a separate PAM service and does not run the normal
    # sddm auth stack. Re-add the GNOME Keyring unlock path there when enabled.
    systemd.services.display-manager.serviceConfig.KeyringMode = lib.mkIf (
      config.features.desktop.login == "autologin"
    ) "inherit";

    security.pam.services."sddm-autologin".rules.auth =
      lib.mkIf (config.features.desktop.login == "autologin")
        {
          systemd_loadkey = {
            order = config.security.pam.services."sddm-autologin".rules.auth.permit.order + 10;
            control = "optional";
            modulePath = "${config.systemd.package}/lib/security/pam_systemd_loadkey.so";
          };
          gnome_keyring = {
            order = config.security.pam.services."sddm-autologin".rules.auth.permit.order + 20;
            control = "optional";
            modulePath = "${pkgs.gnome-keyring}/lib/security/pam_gnome_keyring.so";
            settings.use_authtok = true;
          };
        };

    services = {
      gnome.gnome-keyring.enable = true;
      gvfs.enable = true;
      udisks2.enable = true;
    };
  };
}
