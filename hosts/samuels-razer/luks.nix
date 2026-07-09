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

{ config, lib, ... }:

let
  method = config.features.encryption.unlockMethod;
in
{
  boot.initrd.luks.devices."cryptroot" = {
    device = "/dev/disk/by-partlabel/disk-main-root";
    allowDiscards = true;
    crypttabExtraOpts = [ "tries=0" ];
  };

  boot.initrd.systemd.luks.devices."cryptroot" = lib.mkMerge [
    (lib.mkIf (method == "yubikey") {
      fido2 = {
        enable = true;
        device = "auto";
        credential = "auto";
      };
    })
    (lib.mkIf (method == "tpm2") {
      tpm2.enable = true;
    })
  ];

  # On failure: fall back to password prompt instead of rebooting.
  boot.initrd.systemd.services."systemd-cryptsetup@cryptroot" = {
    overrideStrategy = "asDropin";
    unitConfig.FailureAction = "none";
  };
}
