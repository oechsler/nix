# Disk Configuration (samuels-razer)
#
# Declarative disk partitioning with disko for laptop.
#
# Layout:
# - BOOT: 512MB EFI partition (FAT32, /boot)
# - root: LUKS encrypted Btrfs partition
#   - @ subvolume: / (root, ephemeral - rolled back on boot)
#   - @home subvolume: /home (persistent)
#   - @nix subvolume: /nix (persistent)
#   - @persist subvolume: /persist (persistent)
#   - @steam subvolume: Steam library, persistent but excluded from @home snapshots
#   - @nextcloud subvolume: sync client data, persistent and resyncable
#   - @smb subvolume: persistent mount root for network shares
#   - @snapshots subvolume: /.snapshots (persistent snapshot storage)
#
# Differences from samuels-terra:
# - Laptop form factor, single 1TB NVMe drive
# - No separate games partition
#
# Encryption:
# - LUKS with TPM2 auto-unlock (via luks.nix)
# - Password file at /var/lib/nixos-install/luks-password during installation
#
# Impermanence:
# - Root (/) is ephemeral, rolled back to blank snapshot on reboot
# - Only /home, /nix, /persist survive reboots

# NixOS supplies config.user.name; standalone Disko evaluation supplies
# username explicitly through flake.nix because it has no NixOS config.
moduleArgs:

let
  username =
    moduleArgs.username or (
      if moduleArgs ? config && moduleArgs.config ? user then
        moduleArgs.config.user.name
      else
        throw "samuels-razer/disko.nix requires the global user.name option"
    );
in

{
  disko.devices = {
    disk = {
      main = {
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
                    "@persist" = {
                      mountpoint = "/persist";
                      mountOptions = [
                        "compress=zstd"
                        "noatime"
                      ];
                    };
                    "@steam" = {
                      mountpoint = "/home/${username}/.local/share/Steam";
                    };
                    "@nextcloud" = {
                      mountpoint = "/home/${username}/Nextcloud";
                    };
                    "@smb" = {
                      mountpoint = "/home/${username}/smb";
                    };
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
