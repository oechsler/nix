# Disk Configuration (samuels-ser9)
#
# Declarative disk partitioning with disko.

moduleArgs:

let
  layout = import ../../modules/lib/disko.nix (
    moduleArgs
    // {
      username = moduleArgs.username or "samuel";
    }
  );
  inherit (layout) mainDisk;
in
{
  disko.devices.disk.main = mainDisk "/dev/disk/by-id/nvme-CT1000E100SSD8_2533EADB2554";
}
