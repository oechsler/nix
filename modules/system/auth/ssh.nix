# SSH authentication hardening and second-factor integration.

{ config, lib, ... }:

{
  config = lib.mkIf (config.features.auth.totp.enable || config.features.auth.yubikey.enable) {
    services.openssh.settings = {
      PasswordAuthentication = false;
      AuthenticationMethods = "publickey,keyboard-interactive";
      KbdInteractiveAuthentication = true;
    };
    security.pam.services.sshd.unixAuth = false;
  };
}
