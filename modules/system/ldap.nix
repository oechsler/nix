# LLDAP password authentication for the locally declared primary user.

{
  config,
  lib,
  ...
}:

let
  userName = config.user.name;
  cfg = config.features.auth.ldap;
in
{
  config = lib.mkIf cfg.enable {
    sops.secrets."user/ldap/bind-password" = { };
    sops.secrets."user/ldap/bind-dn" = { };
    sops.secrets."user/ldap/base-dn" = { };
    sops.secrets."user/ldap/host" = { };

    sops.templates."sssd-environment".content = ''
      SSSD_LDAP_DEFAULT_AUTHTOK=${config.sops.placeholder."user/ldap/bind-password"}
      SSSD_LDAP_DEFAULT_BIND_DN=${config.sops.placeholder."user/ldap/bind-dn"}
      SSSD_LDAP_SEARCH_BASE=${config.sops.placeholder."user/ldap/base-dn"}
      SSSD_LDAP_HOST=${config.sops.placeholder."user/ldap/host"}
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
          ldap_uri = "ldaps://$SSSD_LDAP_HOST";
          ldap_id_use_start_tls = false;
          ldap_tls_reqcert = "demand";
          ldap_search_base = "$SSSD_LDAP_SEARCH_BASE";
          ldap_user_search_base = "ou=people,dc=oechsler,dc=it";
          ldap_group_search_base = "ou=groups,dc=oechsler,dc=it";
          ldap_schema = "rfc2307bis";
          ldap_user_object_class = "inetOrgPerson";
          ldap_user_name = "uid";
          ldap_default_bind_dn = "$SSSD_LDAP_DEFAULT_BIND_DN";
          ldap_default_authtok_type = "password";
          ldap_default_authtok = "$SSSD_LDAP_DEFAULT_AUTHTOK";
          cache_credentials = true;
          entry_cache_timeout = 86400;
          simple_allow_users = userName;
        };
      };
    };

    security.pam.services = lib.genAttrs [ "sddm" "sudo" "sshd" ] (_: {
      sssdStrictAccess = true;
    });
  };
}
