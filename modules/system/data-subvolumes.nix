# Large mutable data outside the @home snapshot.
#
# These mounts keep application paths unchanged while preventing large mutable
# data from being copied into hourly @home snapshots.

{ config, lib, ... }:

let
  rootDevice = config.fileSystems."/".device;
  userHome = "/home/${config.user.name}";
  subvolume = name: {
    device = rootDevice;
    fsType = "btrfs";
    options = [
      "subvol=${name}"
      "compress=zstd"
      "noatime"
      "x-gvfs-hide"
    ];
  };
in
{
  config.fileSystems =
    lib.optionalAttrs (config.features.snapshots.enable && config.features.gaming.enable) {
      "${userHome}/.local/share/Steam" = subvolume "@steam";
    }
    // lib.optionalAttrs (config.features.snapshots.enable && config.features.apps.nextcloud.enable) {
      "${userHome}/Nextcloud" = subvolume "@nextcloud";
    }
    //
      lib.optionalAttrs
        (
          config.features.snapshots.enable && config.features.smb.enable && config.features.smb.shares != [ ]
        )
        {
          "${userHome}/smb" = subvolume "@smb";
        }
    //
      lib.optionalAttrs
        (
          !config.features.impermanence.enable
          && config.features.virtualisation.enable
          && config.features.virtualisation.vm.enable
        )
        {
          "/etc/libvirt" = subvolume "@libvirt";
        };
}
