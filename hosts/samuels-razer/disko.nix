# Disk Configuration (samuels-razer)
#
# Declarative disk partitioning with disko for laptop.

moduleArgs:

let
  diskoLayout = import ../../modules/lib/disko-layout.nix moduleArgs;
in
{
  disko.devices.disk.main = {
    type = "disk";
    device = "/dev/disk/by-id/nvme-Samsung_SSD_980_1TB_S649NL0W348323A";
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
          content = diskoLayout;
        };
      };
    };
  };
}
