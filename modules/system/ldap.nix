# LLDAP password authentication for the locally declared primary user.
# SSSD provides LDAP authentication and credential caching. Local users remain
# authoritative for the actual system account and its permissions.

{
  config,
  lib,
  ...
}:

let
  userName = config.user.name;
  cfg = config.features.auth.ldap;
  ldapUri = if cfg.uri == null then "" else cfg.uri;
  baseDn = if cfg.baseDn == null then "" else cfg.baseDn;
  bindDn = if cfg.bindDn == null then "" else cfg.bindDn;
in
{
  options.features.auth.ldap = {
    uri = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "LDAP URI for this host, for example ldaps://ldap.example.org:6360.";
    };
    baseDn = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "LDAP search base for this host.";
    };
    bindDn = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "LDAP bind DN for this host.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.uri != null && cfg.baseDn != null && cfg.bindDn != null;
        message = "features.auth.ldap.uri, baseDn, and bindDn must be set when LDAP is enabled.";
      }
    ];

    sops.secrets = {
      "user/ldap/bind-password" = { };
    };

    sops.templates."sssd-environment".content = ''
      SSSD_LDAP_DEFAULT_AUTHTOK=${config.sops.placeholder."user/ldap/bind-password"}
    '';

    services.sssd = {
      enable = true;
      environmentFile = config.sops.templates."sssd-environment".path;
      settings = {
        sssd = {
          services = "nss, pam";
          domains = "lldap";
          config_file_version = 2;
        };

        nss.enumerate = false;

        pam = {
          offline_credentials_expiration = 0;
          offline_failed_login_attempts = 3;
          offline_failed_login_delay = 5;
        };

        "domain/lldap" = {
          id_provider = "ldap";
          auth_provider = "ldap";
          access_provider = "simple";

          ldap_uri = ldapUri;
          ldap_id_use_start_tls = false;
          ldap_tls_reqcert = "demand";
          ldap_search_base = baseDn;
          ldap_user_search_base = baseDn;
          ldap_group_search_base = baseDn;
          ldap_schema = "rfc2307bis";
          ldap_user_object_class = "person";
          ldap_user_name = "uid";
          ldap_default_bind_dn = bindDn;
          ldap_default_authtok_type = "password";
          ldap_default_authtok = "$SSSD_LDAP_DEFAULT_AUTHTOK";

          cache_credentials = true;
          simple_allow_users = userName;
        };
      };
    };

    # SSSD contributes only PAM authentication. Local passwd/group databases
    # remain authoritative for users, groups, UID/GID, home, and shell.
    security.pam.services = lib.genAttrs [ "sddm" "sudo" "sshd" ] (_: {
      sssdStrictAccess = true;
    });
  };
}
