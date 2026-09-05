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
#   - @persist subvolume: /persist (only with impermanence)
#   - @var subvolume: /var (only without impermanence)
#   - @ssh subvolume: /etc/ssh (SSH, only without impermanence)
#   - @libvirt subvolume: /etc/libvirt (VMs, only without impermanence)
#   - @snapshots subvolume: /.snapshots (persistent snapshot storage)
#   - @steam subvolume: Steam library (when gaming is enabled)
#   - @nextcloud subvolume: sync client data (when Nextcloud is enabled)
#   - @smb subvolume: network shares (when SMB shares are enabled)
#
# Encryption:
# - LUKS with TPM2 auto-unlock (via luks.nix)
# - Password file at /var/lib/nixos-install/luks-password during installation
#
# Impermanence:
# - Root (/) is ephemeral, rolled back to blank snapshot on reboot
# - Only /home, /nix, /persist survive reboots
#
# Feature-specific data subvolumes are created only when their features are
# enabled.
moduleArgs:

let
  username = moduleArgs.username or "samuel";
  features =
    if moduleArgs ? config && moduleArgs.config ? features then moduleArgs.config.features else { };
  impermanenceEnabled = features.impermanence.enable or false;
  encryptionEnabled = features.encryption.enable or false;
  snapshotsEnabled = features.snapshots.enable or false;
  gamingEnabled = features.gaming.enable or false;
  nextcloudEnabled = features.apps.nextcloud.enable or false;
  smbEnabled = (features.smb.enable or false) && (features.smb.shares or [ ]) != [ ];
  sshEnabled = !impermanenceEnabled && (features.ssh.enable or false);
  libvirtEnabled =
    !impermanenceEnabled
    && (features.virtualisation.enable or false)
    && (features.virtualisation.vm.enable or false);
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
              content =
                let
                  btrfsContent = {
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
                    // (
                      if snapshotsEnabled then
                        {
                          "@snapshots" = {
                            mountpoint = "/.snapshots";
                            mountOptions = [
                              "compress=zstd"
                              "noatime"
                            ];
                          };
                        }
                      else
                        { }
                    )
                    // (
                      if gamingEnabled then
                        {
                          "@steam" = {
                            mountpoint = "/home/${username}/.local/share/Steam";
                          };
                        }
                      else
                        { }
                    )
                    // (
                      if nextcloudEnabled then
                        {
                          "@nextcloud" = {
                            mountpoint = "/home/${username}/Nextcloud";
                          };
                        }
                      else
                        { }
                    )
                    // (
                      if sshEnabled then
                        {
                          "@ssh" = {
                            mountpoint = "/etc/ssh";
                          };
                        }
                      else
                        { }
                    )
                    // (
                      if libvirtEnabled then
                        {
                          "@libvirt" = {
                            mountpoint = "/etc/libvirt";
                          };
                        }
                      else
                        { }
                    )
                    // (
                      if smbEnabled then
                        {
                          "@smb" = {
                            mountpoint = "/home/${username}/smb";
                          };
                        }
                      else
                        { }
                    );
                  };
                in
                if encryptionEnabled then
                  {
                    type = "luks";
                    name = "cryptroot";
                    settings.allowDiscards = true;
                    passwordFile = "/var/lib/nixos-install/luks-password";
                    content = btrfsContent;
                  }
                else
                  btrfsContent;
            };
          };
        };
      };
    };
  };
}
