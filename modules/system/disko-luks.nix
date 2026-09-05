# Derive initrd LUKS devices from the host's Disko layout.

{ config, lib, ... }:

let
  unlockOpts = {
    yubikey = [
      "fido2-device=auto"
      "token-timeout=30s"
    ];
    tpm2 = [ "tpm2-device=auto" ];
    password = [ ];
  };

  luksDevices = lib.listToAttrs (
    lib.concatMap (
      diskName:
      let
        disk = config.disko.devices.disk.${diskName};
        partitions = disk.content.partitions or { };
      in
      lib.concatMap (
        partitionName:
        let
          partition = partitions.${partitionName};
          content = partition.content or { };
        in
        lib.optional (content.type or null == "luks") (
          lib.nameValuePair content.name {
            device = "/dev/disk/by-partlabel/disk-${diskName}-${partitionName}";
            allowDiscards = content.settings.allowDiscards or true;
            crypttabExtraOpts = unlockOpts.${config.features.encryption.unlockMethod};
          }
        )
      ) (lib.attrNames partitions)
    ) (lib.attrNames config.disko.devices.disk)
  );

  cryptrootFailureDropin = lib.optionalAttrs (luksDevices ? cryptroot) {
    "systemd-cryptsetup@cryptroot" = {
      overrideStrategy = "asDropin";
      unitConfig.FailureAction = "none";
    };
  };
in
{
  config = lib.mkIf (luksDevices != { }) {
    boot.initrd = {
      luks.devices = luksDevices;
      systemd.services = cryptrootFailureDropin;
    };
  };
}
