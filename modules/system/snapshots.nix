# Automatic btrfs snapshots with btrbk
#
# Snapshots @home and @persist hourly with automatic cleanup.
# Retention: 24 hourly, 7 daily, 2 weekly, 6 monthly
{ config, lib, pkgs, ... }:

let
  cfg = config.features.snapshots;
in
{
  options.features.snapshots = {
    enable = (lib.mkEnableOption "automatic btrfs snapshots") // { default = true; };
  };

  config = lib.mkIf cfg.enable {
    services.btrbk = {
      instances.default = {
        onCalendar = "hourly";
        settings = {
          timestamp_format = "long";
          snapshot_preserve_min = "2h";
          snapshot_preserve = "24h 7d 2w 6m";

          volume."/mnt/btrfs-root" = {
            snapshot_dir = "@snapshots";

            subvolume."@home" = {
              snapshot_create = "always";
            };

            subvolume."@persist" = {
              snapshot_create = "always";
            };
          };
        };
      };
    };

    # Mount btrfs root (subvol=/) for btrbk to access all subvolumes
    fileSystems."/mnt/btrfs-root" = {
      device = "/dev/mapper/cryptroot";
      fsType = "btrfs";
      options = [ "subvol=/" "compress=zstd" "noatime" ];
    };

    environment.systemPackages = [ pkgs.btrbk ];

    # Symlink so `btrbk run` works without -c flag
    environment.etc."btrbk/btrbk.conf".text = ''
      timestamp_format long
      snapshot_preserve_min 2h
      snapshot_preserve 24h 7d 2w 6m

      volume /mnt/btrfs-root
        snapshot_dir @snapshots
        subvolume @home
          snapshot_create always
        subvolume @persist
          snapshot_create always
    '';
  };
}
