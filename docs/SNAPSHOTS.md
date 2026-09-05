# Btrfs Snapshots

Automatic hourly Btrfs snapshots via btrbk. The feature is enabled by default
when the expected Btrfs layout is present. This guide covers browsing, restoring,
and cleaning snapshots. For the required disk layout, see
[INSTALL.md](INSTALL.md#disk-layout).

## Before You Restore

- Prefer restoring a single file or directory over a full rollback.
- Verify the snapshot timestamp and target path before copying data.
- Run full subvolume rollback only from a recovery environment.
- Snapshots are not backups; keep an independent copy of important data.

## What Gets Snapshotted

| Subvolume  | Mountpoint | Purpose                                                | Condition                                      |
| ---------- | ---------- | ------------------------------------------------------ | ---------------------------------------------- |
| `@`        | `/`        | Root filesystem                                        | Only if `features.impermanence.enable = false` |
| `@home`    | `/home`    | User data, dotfiles                                    | Always                                         |
| `@var`     | `/var`     | Variable system state                                  | Only if `features.impermanence.enable = false` |
| `@persist` | `/persist` | System state (bluetooth, docker, NetworkManager, etc.) | Only if `features.impermanence.enable = true`  |

The root subvolume is not snapshotted while impermanence is enabled because it
is recreated on boot. The Nix store is excluded because it is immutable and
managed by Nix.

The `@steam`, `@nextcloud`, and `@smb` subvolumes are separate from `@home` so
large or independently managed data does not enter hourly home snapshots. They
are not snapshot sources in the default btrbk configuration.

## Retention Policy

Snapshots are taken hourly and automatically cleaned up:

| Keep | Duration                |
| ---- | ----------------------- |
| 24   | Hourly (last 24 hours)  |
| 7    | Daily (last 7 days)     |
| 2    | Weekly (last 2 weeks)   |
| 6    | Monthly (last 6 months) |

## Manage Snapshots

```bash
# Create snapshot now
sudo btrbk run

# List all snapshots
sudo btrbk list snapshots

# Show snapshot details
sudo btrbk list latest

# Dry-run cleanup (see what would be deleted)
sudo btrbk prune --dry-run

# Run cleanup
sudo btrbk prune
```

## Browse Snapshots

Snapshots are stored in `@snapshots`, which is mounted at `/.snapshots/` for
normal browsing:

```bash
ls /.snapshots/
# @home.YYYYMMDDTHHMMSS
# @persist.YYYYMMDDTHHMMSS
# ...
```

The Btrfs top-level is also mounted at `/mnt/btrfs-root` as a convenience view
of all subvolumes:

```bash
# With LUKS encryption:
sudo mount -o subvol=/ /dev/mapper/cryptroot /mnt/btrfs-root

# Without encryption (use your device):
sudo mount -o subvol=/ /dev/nvme0n1p2 /mnt/btrfs-root

ls /mnt/btrfs-root/
# @  @home  @nix  @persist  @snapshots
ls /mnt/btrfs-root/@snapshots/
```

## Restore Data

### Single File

```bash
# Find the snapshot
ls /.snapshots/ | grep @home

# Copy a file from a snapshot
cp /.snapshots/@home.YYYYMMDDTHHMMSS/user/Documents/example.txt ~/Documents/
```

### Directory

```bash
# Restore an entire directory
cp -r /.snapshots/@home.YYYYMMDDTHHMMSS/user/Projects/example ~/Projects/
```

### Full Subvolume Rollback

Full subvolume rollback is a recovery operation. Prefer restoring individual
files first; renaming or deleting subvolumes can destroy data. The procedure
below must be run from a recovery environment where `@home` is not mounted. It
restores `@home`, not the ephemeral root `@`.

```bash
# Mount the Btrfs top-level (adjust the device path)
sudo mount -o subvol=/ /dev/mapper/cryptroot /mnt/btrfs-root
cd /mnt/btrfs-root

# Ensure the active @home is unmounted before continuing.
# Rename the current subvolume
sudo mv @home @home.broken

# Snapshot the backup as new @home
sudo btrfs subvolume snapshot @snapshots/@home.YYYYMMDDTHHMMSS @home

# Reboot
sudo reboot
```

After reboot, verify everything works, then delete the broken one:

```bash
sudo mount -o subvol=/ /dev/mapper/cryptroot /mnt/btrfs-root
sudo btrfs subvolume delete /mnt/btrfs-root/@home.broken
```

## Disable Snapshots

```nix
features = {
  snapshots.enable = false;
};
```

Disabling snapshots stops future snapshot jobs; it does not delete existing
snapshots.
