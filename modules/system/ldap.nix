# LLDAP password authentication for the locally declared primary user.
# The PAM module checks only the password and keeps an Argon2id offline cache.

{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.features.auth.ldap;
  userName = config.user.name;
  uri = if cfg.uri == null then "" else cfg.uri;
  baseDn = if cfg.baseDn == null then "" else cfg.baseDn;
  userDn = "uid=${userName},ou=people,${baseDn}";
  cachePath = "/var/lib/pam-lldap/${userName}.hash";
  isKde = config.features.desktop.wm == "kde";
in
{
  options.features.auth.ldap = {
    uri = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "LDAP URI for this host.";
    };
    baseDn = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "LDAP base DN for this host.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.uri != null && cfg.baseDn != null;
        message = "features.auth.ldap.uri and baseDn must be set when LDAP is enabled.";
      }
    ];

    # hyprlock authenticates as the desktop user rather than as root. The
    # verifier therefore needs to be private to that user, while still being
    # readable by privileged PAM consumers such as login and SDDM.
    systemd.tmpfiles.rules = [
      "d /var/lib/pam-lldap 0700 ${userName} ${config.users.users.${userName}.group} -"
      "f ${cachePath} 0600 ${userName} ${config.users.users.${userName}.group} -"
    ];

    security.pam.services = lib.mkMerge [
      (lib.genAttrs [ "login" "sudo" "polkit-1" "hyprlock" "sshd" ] (_: {
        unixAuth = false;
        rules.auth.pam_lldap = {
          order = 12000;
          # Do not short-circuit here: the following keyring module must see
          # the password in PAM_AUTHTOK after LDAP authentication succeeds.
          control = "required";
          modulePath = "${pkgs.pam-lldap}/lib/security/pam_lldap.so";
          args = [
            "uri=${uri}"
            "user_dn=${userDn}"
            "user=${userName}"
            "cache=${cachePath}"
          ];
        };
        rules.auth.deny.enable = false;
      }))
      {
        # pam_lldap obtains PAM_AUTHTOK, then the desktop keyring modules reuse
        # it to unlock GNOME Keyring or KWallet without prompting again.
        login.rules.auth.gnome_keyring = {
          enable = !isKde;
          order = 12100;
          control = "optional";
          modulePath = "${pkgs.gnome-keyring}/lib/security/pam_gnome_keyring.so";
          settings.use_authtok = true;
        };
        login.rules.auth.kwallet = {
          enable = isKde;
          order = 12100;
          control = "optional";
          modulePath = "${config.security.pam.services.login.kwallet.package}/lib/security/pam_kwallet5.so";
          settings.use_authtok = true;
        };
        sddm.rules.auth.gnome_keyring = {
          enable = !isKde;
          order = 12100;
          control = "optional";
          modulePath = "${pkgs.gnome-keyring}/lib/security/pam_gnome_keyring.so";
          settings.use_authtok = true;
        };
        sddm.rules.auth.kwallet = {
          enable = isKde;
          order = 12100;
          control = "optional";
          modulePath = "${config.security.pam.services.sddm.kwallet.package}/lib/security/pam_kwallet5.so";
          settings.use_authtok = true;
        };
      }
    ];
  };
}
