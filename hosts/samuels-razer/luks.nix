# LUKS Encryption Configuration (samuels-razer)
#
# Encrypted device:
# - cryptroot: System partition (root, home, nix, persist)
#
# Unlock method:
#   features.encryption.unlockMethod = "yubikey"  → FIDO2 touch at boot
#   features.encryption.unlockMethod = "tpm2"     → TPM2 auto-unlock
#   features.encryption.unlockMethod = "password" → LUKS passphrase prompt
#
# Setup:
#   YubiKey: yubikey-luks-init
#   TPM2:    tpm-luks-init
#
# Differences from samuels-pc:
# - Only one encrypted partition (no separate games partition)

{ config, lib, ... }:

let
  method = config.features.encryption.unlockMethod;
in
{
  boot.initrd.luks.devices."cryptroot" = {
    device = "/dev/disk/by-partlabel/disk-main-root";
    allowDiscards = true;
    crypttabExtraOpts = [ "tries=0" ];
    fido2 = lib.mkIf (method == "yubikey") {
      enable = true;
      credential = "auto";
      passwordLessMode = false;
    };
    tpm2 = lib.mkIf (method == "tpm2") {
      enable = true;
    };
  };

  # On failure: fall back to password prompt instead of rebooting.
  boot.initrd.systemd.services."systemd-cryptsetup@cryptroot" = {
    overrideStrategy = "asDropin";
    unitConfig.FailureAction = "none";
  };
}
