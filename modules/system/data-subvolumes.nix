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
  config = lib.mkIf config.features.snapshots.enable {
    fileSystems = {
      "${userHome}/.local/share/Steam" = subvolume "@steam";
      "${userHome}/smb" = subvolume "@smb";
    }
    // lib.optionalAttrs config.features.apps.nextcloud.enable {
      "${userHome}/Nextcloud" = subvolume "@nextcloud";
    };
  };
}
