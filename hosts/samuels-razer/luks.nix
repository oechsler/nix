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
  luks = import ../../modules/lib/luks.nix { inherit config lib; };
in
{
  boot.initrd = luks.mkInitrd {
    devices.cryptroot = {
      disk = "main";
      partition = "root";
    };
  };
}
