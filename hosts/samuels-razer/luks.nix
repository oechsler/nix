# LUKS Encryption Configuration (samuels-razer)
#
# TPM2-based auto-unlock for encrypted system partition.
#
# Encrypted device:
# - cryptroot: System partition (root, home, nix, persist)
#
# TPM2 auto-unlock:
# - Unlocks automatically on boot without password prompt
# - Sealed to PCR0 (firmware) + PCR7 (Secure Boot)
# - Falls back to password prompt if TPM state changes
#
# Setup:
# 1. Install with LUKS password (disko uses /tmp/luks-password)
# 2. Enroll TPM2: systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=0+7 /dev/disk/by-partlabel/disk-main-root
#
# Differences from samuels-pc:
# - Only one encrypted partition (no separate games partition)

{ ... }:

{
  boot.initrd.luks.devices = {
    "cryptroot" = {
      device = "/dev/disk/by-partlabel/disk-main-root";
      allowDiscards = true;
      crypttabExtraOpts = [ "tpm2-device=auto" ];
    };
  };
}
