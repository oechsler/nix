# Authentication feature options.

{ config, lib, ... }:

{
  options.features.auth = {
    totp.enable = (lib.mkEnableOption "TOTP two-factor authentication") // {
      default = true;
    };
    yubikey.enable = lib.mkOption {
      type = lib.types.bool;
      default = config.features.encryption.unlockMethod == "yubikey";
      description = "Enable YubiKey authentication tools and PAM integration.";
    };
    ldap.enable = (lib.mkEnableOption "LLDAP authentication") // {
      default = false;
    };
  };
}
