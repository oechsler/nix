# Disk Configuration (samuels-terra)
#
# Declarative disk partitioning with disko.
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
# Encryption:
# - LUKS with YubiKey FIDO2 unlock (via luks.nix)
# - Password file at /var/lib/nixos-install/luks-password during installation
#
# Impermanence:
# - Root (/) is ephemeral, rolled back to blank snapshot on reboot
# - Only /home, /nix, /persist survive reboots
# - See modules/system/impermanence.nix for persistence config

# NixOS supplies config.user.name; standalone Disko evaluation supplies
# username explicitly through flake.nix because it has no NixOS config.
moduleArgs:

let
  username =
    moduleArgs.username or (
      if moduleArgs ? config && moduleArgs.config ? user then
        moduleArgs.config.user.name
      else
        throw "samuels-terra/disko.nix requires the global user.name option"
    );
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
        device = "/dev/disk/by-id/nvme-Samsung_SSD_9100_PRO_2TB_S7YFNJ0L208614L";
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
                      { }
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
