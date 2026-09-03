# Cross-feature assertions and warnings.

{ config, lib, ... }:

let
  isAutologin = config.features.desktop.login == "autologin";
  hasYubiKey = config.features.auth.yubikey.enable;
  hasTotp = config.features.auth.totp.enable;
in
{
  config = lib.mkMerge [
    {
      warnings =
        lib.optional (isAutologin && config.features.encryption.unlockMethod != "password")
          "features.desktop.login = 'autologin' with features.encryption.unlockMethod = '${config.features.encryption.unlockMethod}' can start the session with a locked keyring. Use desktop.login = 'greeter' or encryption.unlockMethod = 'password' if you want to avoid later keyring password prompts."
        ++
          lib.optional (isAutologin && config.features.encryption.unlockMethod == "password")
            "For password autologin, keep LUKS passphrase, user password, and keyring password identical. NixOS cannot enforce this."
        ++
          lib.optional (hasYubiKey && !hasTotp)
            "features.auth.yubikey.enable = true without features.auth.totp.enable = true leaves sudo with no TOTP fallback. If your YubiKey is unavailable, sudo falls through to plain password.";

      assertions = [
        {
          assertion = config.features.encryption.unlockMethod != "yubikey" || hasYubiKey;
          message = "features.encryption.unlockMethod = 'yubikey' requires features.auth.yubikey.enable = true. Set auth.yubikey.enable = true or change encryption.unlockMethod.";
        }
        {
          assertion = !config.features.encryption.enable || config.boot.initrd.luks.devices != { };
          message = "features.encryption.enable = true requires a LUKS device in the host's disko.nix. If the host uses no encryption, set features.encryption.enable = false.";
        }
      ];
    }
  ];
}
