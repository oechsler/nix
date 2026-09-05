# Disk Configuration (samuels-ser9)
#
# Declarative disk partitioning with disko.
#
# Layout:
# - BOOT: 512MB EFI partition (FAT32, /boot)
# - root: LUKS encrypted Btrfs partition
#   - @ subvolume: / (root, ephemeral - rolled back on boot)
#   - @home subvolume: /home (persistent)
#   - @nix subvolume: /nix (persistent)
#   - @var subvolume: /var (only without impermanence)
#   - @persist subvolume: /persist (persistent)
#   - @snapshots subvolume: /.snapshots (persistent snapshot storage)
#
# Encryption:
# - LUKS with TPM2 auto-unlock (via luks.nix)
# - Password file at /var/lib/nixos-install/luks-password during installation
#
# Impermanence:
# - Root (/) is ephemeral, rolled back to blank snapshot on reboot
# - Only /home, /nix, /persist survive reboots
#
# This host has no feature-specific data subvolumes and does not require
# username arguments when Disko is evaluated standalone.
moduleArgs:

let
  impermanenceEnabled =
    moduleArgs ? config
    && moduleArgs.config ? features
    && moduleArgs.config.features.impermanence.enable;
in

{
  disko.devices = {
    disk = {
      main = {
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
              content = {
                type = "luks";
                name = "cryptroot";
                settings.allowDiscards = true;
                passwordFile = "/var/lib/nixos-install/luks-password";
                content = {
                  type = "btrfs";
                  extraArgs = [
                    "-f"
                    "-L"
                    "nixos"
                  ];
                  subvolumes = {
                    "@" = {
                      mountpoint = "/";
                      mountOptions = [
                        "compress=zstd"
                        "noatime"
                      ];
                    };
                    "@home" = {
                      mountpoint = "/home";
                      mountOptions = [
                        "compress=zstd"
                        "noatime"
                      ];
                    };
                    "@nix" = {
                      mountpoint = "/nix";
                      mountOptions = [
                        "compress=zstd"
                        "noatime"
                      ];
                    };
                  }
                  // (
                    if impermanenceEnabled then
                      {
                        "@persist" = {
                          mountpoint = "/persist";
                          mountOptions = [
                            "compress=zstd"
                            "noatime"
                          ];
                        };
                      }
                    else
                      {
                        "@var" = {
                          mountpoint = "/var";
                          mountOptions = [
                            "compress=zstd"
                            "noatime"
                          ];
                        };
                      }
                  )
                  // {
                    "@snapshots" = {
                      mountpoint = "/.snapshots";
                      mountOptions = [
                        "compress=zstd"
                        "noatime"
                      ];
                    };
                  };
                };
              };
            };
          };
        };
      };
    };
  };
}
