# Disk Configuration (samuels-ser9)
#
# Declarative disk partitioning with disko.

moduleArgs:

let
  rootLayout = import ../../modules/lib/disko.nix (
    moduleArgs
    // {
      username = moduleArgs.username or "samuel";
    }
  );
in
{
  disko.devices.disk.main = {
    type = "disk";
    device = "/dev/disk/by-id/nvme-CT1000E100SSD8_2533EADB2554";
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
