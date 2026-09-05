# Disk Configuration (samuels-razer)
#
# Declarative disk partitioning with disko for laptop.

moduleArgs:

let
  layout = import ../../modules/lib/disko.nix moduleArgs;
  inherit (layout) mainDisk;
in
{
  disko.devices.disk.main = mainDisk "/dev/disk/by-id/nvme-Samsung_SSD_980_1TB_S649NL0W348323A";
}
