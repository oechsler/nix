# Encryption and secure-boot feature options.

{ lib, ... }:

{
  options.features.encryption = {
    enable = (lib.mkEnableOption "LUKS full disk encryption") // {
      default = true;
    };
    unlockMethod = lib.mkOption {
      type = lib.types.enum [
        "yubikey"
        "tpm2"
        "password"
      ];
      default = "tpm2";
      description = "How LUKS devices are unlocked at boot.";
    };
  };
}
