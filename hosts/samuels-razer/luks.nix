# LUKS Encryption Configuration (samuels-razer)
#
# Encrypted device:
# - cryptroot: System partition (root, home, nix, persist)
#
# Unlock method:
#   features.auth.yubikey.luks.enable = true;  → fido2-device=auto (YubiKey FIDO2 touch at boot)
#   features.auth.yubikey.luks.enable = false; → tpm2-device=auto  (TPM2 auto-unlock, default)
#
# Setup:
#   YubiKey: yubikey-luks-init
#   TPM2:    tpm-luks-init
#
# Differences from samuels-pc:
# - Only one encrypted partition (no separate games partition)

{ config, ... }:

let
  unlockOpt = if config.features.auth.yubikey.luks.enable
    then "fido2-device=auto"
    else "tpm2-device=auto";
in {
  boot.initrd.luks.devices = {
    "cryptroot" = {
      device = "/dev/disk/by-partlabel/disk-main-root";
      allowDiscards = true;
      crypttabExtraOpts = [ unlockOpt ];
    };
  };

  # cryptroot failing → reboot (system can't boot without it)
  boot.initrd.systemd.services."systemd-cryptsetup@cryptroot" = {
    overrideStrategy = "asDropin";
    unitConfig.FailureAction = "reboot-force";
  };
}
