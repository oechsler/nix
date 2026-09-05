# Disk Configuration (samuels-terra)
#
# Declarative disk partitioning with disko.

moduleArgs:

let
  diskLayout = import ../../modules/lib/disko.nix moduleArgs;
  inherit (diskLayout) efiLayout rootLayout;
in
{
  disko.devices.disk.main = {
    type = "disk";
    device = "/dev/disk/by-id/nvme-Samsung_SSD_9100_PRO_2TB_S7YFNJ0L208614L";
    content = {
      type = "gpt";
      partitions = {
        BOOT = efiLayout;
        root = {
          size = "100%";
          content = rootLayout;
        };
      };
    };
  };
}
