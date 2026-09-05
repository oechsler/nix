# Disk Configuration (samuels-razer)
#
# Declarative disk partitioning with disko for laptop.

moduleArgs:

let
  diskLayout = import ../../modules/lib/disko.nix moduleArgs;
  inherit (diskLayout) efiLayout rootLayout;
in
{
  disko.devices.disk.main = {
    type = "disk";
    device = "/dev/disk/by-id/nvme-Samsung_SSD_980_1TB_S649NL0W348323A";
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
