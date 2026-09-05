# Disk Configuration (samuels-terra)
#
# Declarative disk partitioning with disko.

moduleArgs:

let
  rootLayout = import ../../modules/lib/disko.nix moduleArgs;
in
{
  disko.devices.disk.main = {
    type = "disk";
    device = "/dev/disk/by-id/nvme-Samsung_SSD_9100_PRO_2TB_S7YFNJ0L208614L";
    content = {
      type = "gpt";
      partitions = {
        BOOT = {
          size = "512M";
          type = "EF00";
          content = {
            type = "filesystem";
            format = "vfat";
            mountpoint = "/boot";
            mountOptions = [ "umask=0077" ];
            extraArgs = [
              "-n"
              "BOOT"
            ];
          };
        };
        root = {
          size = "100%";
          content = rootLayout;
        };
      };
    };
  };
}
