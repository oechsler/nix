# Automatic Btrfs Snapshots Configuration
#
# This module configures:
# 1. Automatic hourly snapshots of important subvolumes
# 2. Automatic cleanup with retention policy
# 3. Snapshot access via /mnt/btrfs-root/@snapshots
#
# Configuration options:
#   features.snapshots.enable = true;  # Enable automatic snapshots (default: true)
#
# Snapshot schedule:
#   - Runs: Every hour
#   - Subvolumes: @home, @persist
#   - Subvolumes (conditional): @ (only if impermanence is disabled)
#   - Storage: /mnt/btrfs-root/@snapshots/
#
# Retention policy:
#   - Minimum: 2 hours (don't delete snapshots younger than 2h)
#   - Hourly: 24 (last 24 hours)
#   - Daily: 7 (last 7 days)
#   - Weekly: 2 (last 2 weeks)
#   - Monthly: 6 (last 6 months)
#
# How to restore:
#   1. List snapshots: ls /mnt/btrfs-root/@snapshots/
#   2. Browse snapshot: ls /mnt/btrfs-root/@snapshots/@home.20240315T120000/
#   3. Copy files: cp -a /mnt/btrfs-root/@snapshots/@home.20240315T120000/file ~/

{ config, lib, pkgs, ... }:

let
  cfg = config.features.snapshots;
in
{
  #===========================
  # Options
  #===========================

  options.features.snapshots = {
    enable = (lib.mkEnableOption "automatic btrfs snapshots") // { default = true; };
  };

  #===========================
  # Configuration
  #===========================

  config = lib.mkIf cfg.enable {

    #---------------------------
    # 1. Snapshot Service (btrbk)
    #---------------------------
    services.btrbk = {
      instances.default = {
        onCalendar = "hourly";  # Run every hour
        settings = {
          timestamp_format = "long";  # ISO 8601 format (e.g., 20240315T120000)
          snapshot_preserve_min = "2h";  # Don't delete snapshots younger than 2h
          snapshot_preserve = "24h 7d 2w 6m";  # Retention: 24 hourly, 7 daily, 2 weekly, 6 monthly

          volume."/mnt/btrfs-root" = {
            snapshot_dir = "@snapshots";  # Store snapshots in @snapshots subvolume

            # Snapshot subvolumes
            # - @ (root): Only if impermanence disabled (otherwise wiped on boot)
            # - @home: Always (user data)
            # - @persist: Only if impermanence enabled (otherwise unused)
            subvolume = lib.mkMerge [
              (lib.mkIf (!config.features.impermanence.enable) {
                "@" = {
                  snapshot_create = "always";
                };
              })
              (lib.mkIf config.features.impermanence.enable {
                "@persist" = {
                  snapshot_create = "always";
                };
              })
              {
                "@home" = {
                  snapshot_create = "always";
                };
              }
            ];
          };
        };
      };
    };

    #---------------------------
    # 2. Btrfs Root Mount
    #---------------------------
    # Mount btrfs root (subvol=/) so btrbk can access all subvolumes
    # This is separate from the main root mount (which mounts subvol=@)
    #
    # Device detection: Use same device as root filesystem
    # Works with both LUKS (/dev/mapper/cryptroot) and direct devices
    fileSystems."/mnt/btrfs-root" = {
      inherit (config.fileSystems."/") device;
      fsType = "btrfs";
      options = [
        "subvol=/"       # Mount btrfs root, not @ subvolume
        "compress=zstd"  # Enable compression
        "noatime"        # Don't update access times (performance)
        "x-gvfs-hide"    # Hide from file managers (it's a technical mount)
      ];
    };

    #---------------------------
    # 3. btrbk CLI Tool
    #---------------------------
    environment.systemPackages = [ pkgs.btrbk ];

    #---------------------------
    # 4. btrbk Configuration File
    #---------------------------
    # Create /etc/btrbk/btrbk.conf so `btrbk run` works without -c flag
    # This is a symlink to the systemd service config
    environment.etc."btrbk/btrbk.conf".text = ''
      timestamp_format long
      snapshot_preserve_min 2h
      snapshot_preserve 24h 7d 2w 6m

      volume /mnt/btrfs-root
        snapshot_dir @snapshots
        ${lib.optionalString (!config.features.impermanence.enable) ''
      subvolume @
        snapshot_create always
        ''}
      subvolume @home
        snapshot_create always
        ${lib.optionalString config.features.impermanence.enable ''
      subvolume @persist
        snapshot_create always
        ''}
    '';
  };
}
