# Btrfs Snapshots

Automatic hourly snapshots via btrbk. Enabled by default.

## What Gets Snapshotted

| Subvolume | Mountpoint | Purpose | Condition |
|-----------|------------|---------|-----------|
| `@` | `/` | Root filesystem | Only if `features.impermanence.enable = false` |
| `@home` | `/home` | User data, dotfiles | Always |
| `@persist` | `/persist` | System state (bluetooth, docker, NetworkManager, etc.) | Only if `features.impermanence.enable = true` |

Not snapshotted:
- `@` (root) — when impermanence enabled (wiped on boot anyway)
- `@persist` — when impermanence disabled (unused/unnecessary)
- `@nix` — immutable, managed by Nix

## Retention Policy

Snapshots are taken hourly and automatically cleaned up:

| Keep | Duration |
|------|----------|
| 24 | Hourly (last 24 hours) |
| 7 | Daily (last 7 days) |
| 2 | Weekly (last 2 weeks) |
| 6 | Monthly (last 6 months) |

## Commands

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

Snapshots are stored in `/.snapshots/` (mounted at boot). Browse directly:

```bash
ls /.snapshots/
# @home.20250215T1400
# @home.20250215T1300
# @persist.20250215T1400
# ...
```

Or mount the btrfs root to see all subvolumes:

```bash
# With LUKS encryption:
sudo mount -o subvol=/ /dev/mapper/cryptroot /mnt/btrfs-root

# Without encryption (use your device):
sudo mount -o subvol=/ /dev/nvme0n1p2 /mnt/btrfs-root

ls /mnt/btrfs-root/
# @  @home  @nix  @persist  @snapshots
ls /mnt/btrfs-root/@snapshots/
```

## Restore Files

### Single File

```bash
# Find the snapshot
ls /.snapshots/ | grep @home

# Copy file from snapshot
cp /.snapshots/@home.20250215T1400/samuel/Documents/wichtig.txt ~/Documents/
```

### Directory

```bash
# Restore entire directory
cp -r /.snapshots/@home.20250215T1400/samuel/Projects/myproject ~/Projects/
```

### Full Subvolume Rollback

For a complete rollback (e.g., after a broken config change):

```bash
# Mount btrfs root (adjust device path: /dev/mapper/cryptroot or /dev/nvme0n1p2)
sudo mount -o subvol=/ /dev/mapper/cryptroot /mnt/btrfs-root
cd /mnt/btrfs-root

# Rename current subvolume
sudo mv @home @home.broken

# Snapshot the backup as new @home
sudo btrfs subvolume snapshot @snapshots/@home.20250215T1400 @home

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
features.snapshots.enable = false;
```
