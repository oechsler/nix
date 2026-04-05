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

{ config, lib, ... }:

let
  unlockOpt = if config.features.auth.yubikey.luks.enable
    then "fido2-device=auto"
    else "tpm2-device=auto";

  luksDevices = config.boot.initrd.luks.devices;
in {
  boot.initrd.luks.devices = {
    "cryptroot" = {
      device = "/dev/disk/by-partlabel/disk-main-root";
      allowDiscards = true;
      crypttabExtraOpts = [ unlockOpt ];
    };
  };

  # Give 15 minutes to unlock (e.g. find YubiKey).
  # cryptroot failing → poweroff (system can't boot without it).
  # Other devices → timeout only, no poweroff.
  boot.initrd.systemd.services = lib.mapAttrs' (name: _: {
    name = "systemd-cryptsetup@${name}";
    value = {
      overrideStrategy = "asDropin";
      serviceConfig.TimeoutStartSec = "900";
    } // lib.optionalAttrs (name == "cryptroot") {
      unitConfig.FailureAction = "poweroff-force";
    };
  }) luksDevices;
}
