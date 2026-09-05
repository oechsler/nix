# Disk Configuration (samuels-ser9)
#
# Declarative disk partitioning with disko.

moduleArgs:

let
  diskLayout = import ../../modules/lib/disko.nix (
    moduleArgs
    // {
      username = moduleArgs.username or "samuel";
    }
  );
  inherit (diskLayout) efiLayout rootLayout;
in
{
  disko.devices.disk.main = {
    type = "disk";
    device = "/dev/disk/by-id/nvme-CT1000E100SSD8_2533EADB2554";
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
