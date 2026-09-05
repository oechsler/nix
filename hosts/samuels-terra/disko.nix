# Disk Configuration (samuels-terra)
#
# Declarative disk partitioning with disko.

moduleArgs:

let
  layout = import ../../modules/lib/disko.nix moduleArgs;
  inherit (layout) mainDisk;
in
{
  disko.devices.disk.main = mainDisk "/dev/disk/by-id/nvme-Samsung_SSD_9100_PRO_2TB_S7YFNJ0L208614L";
}
