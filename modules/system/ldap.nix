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

    systemd.tmpfiles.rules = [ "d /var/lib/pam-lldap 0700 root root -" ];

    security.pam.services = lib.genAttrs [ "login" "sddm" "sudo" "polkit-1" "hyprlock" ] (_: {
      unixAuth = false;
      rules.auth.pam_lldap = {
        order = 12000;
        control = "sufficient";
        modulePath = "${pkgs.pam-lldap}/lib/security/pam_lldap.so";
        args = [
          "uri=${uri}"
          "user_dn=${userDn}"
          "user=${userName}"
          "cache=${cachePath}"
        ];
      };
    });
  };
}
