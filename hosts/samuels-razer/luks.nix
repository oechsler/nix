# LUKS Encryption Configuration (samuels-razer)
#
# Encrypted device:
# - cryptroot: System partition (root, home, nix, persist)
#
# Unlock method:
#   features.encryption.unlockMethod = "yubikey"  → fido2-device=auto (YubiKey FIDO2 touch at boot)
#   features.encryption.unlockMethod = "tpm2"     → tpm2-device=auto  (TPM2 auto-unlock, default)
#   features.encryption.unlockMethod = "password" → prompt for LUKS passphrase
#
# Setup:
#   YubiKey: yubikey-luks-init
#   TPM2:    tpm-luks-init
#
# Differences from samuels-pc:
# - Only one encrypted partition (no separate games partition)

{ config, ... }:

let
  unlockOpts = {
    yubikey = [ "fido2-device=auto" "fido2-no-client-pin" "tries=0" ];
    tpm2 = [ "tpm2-device=auto" "tries=0" ];
    password = [ "tries=0" ];
  };
in
{
  boot.initrd.luks.devices = {
    "cryptroot" = {
      device = "/dev/disk/by-partlabel/disk-main-root";
      allowDiscards = true;
      crypttabExtraOpts = unlockOpts.${config.features.encryption.unlockMethod};
    };
  };

  # On failure: fall back to password prompt instead of rebooting.
  boot.initrd.systemd.services."systemd-cryptsetup@cryptroot" = {
    overrideStrategy = "asDropin";
    unitConfig.FailureAction = "none";
  };
}
