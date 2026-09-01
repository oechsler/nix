# Hyprland System Configuration
#
# System packages and services for Hyprland. User-level configuration lives in
# home-manager/desktop/hyprland/.
#
# Provides Hyprland/UWSM, the Hyprland and GTK portals, authentication dialogs,
# and the shared keyring, filesystem, and removable-media services needed by
# the session.
#
# When autologin uses a cached password unlock, extend the separate SDDM
# autologin PAM stack so GNOME Keyring can be unlocked with the session.
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
      gnome-disk-utility
      hyprpolkitagent
    ];

    xdg.portal = {
      enable = true;
      # Hyprland portal handles screen/input; GTK portal handles Settings
      # (color-scheme for WebKitGTK/Tauri apps)
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

    # Pass the SDDM login password (local or LDAP) to GNOME Keyring.
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
