# LUKS Helpers
#
# Shared helpers for host LUKS initrd declarations.

{ config, lib }:

let
  unlockOpts = {
    yubikey = [
      "fido2-device=auto"
      "token-timeout=30s"
    ];
    tpm2 = [ "tpm2-device=auto" ];
    password = [ ];
  };

  mkPartLabel = disk: partition: "/dev/disk/by-partlabel/disk-${disk}-${partition}";

  mkDevice =
    {
      disk,
      partition,
      allowDiscards ? true,
    }:
    {
      device = mkPartLabel disk partition;
      inherit allowDiscards;
      crypttabExtraOpts = unlockOpts.${config.features.encryption.unlockMethod};
    };

  mkNoFailureService = name: {
    name = "systemd-cryptsetup@${name}";
    value = {
      overrideStrategy = "asDropin";
      unitConfig.FailureAction = "none";
    };
  };
in
{
  mkInitrd =
    {
      devices,
      noFailureDevices ? [ "cryptroot" ],
    }:
    lib.mkIf config.features.encryption.enable {
      luks.devices = lib.mapAttrs (_: mkDevice) devices;
      # Do not reboot the machine when FIDO2 unlock fails or times out.
      systemd.services = lib.listToAttrs (map mkNoFailureService noFailureDevices);
    };
}
