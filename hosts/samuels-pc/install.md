# NixOS Installation Guide for samuels-pc

This guide describes how to install NixOS on `samuels-pc` using disko for declarative disk partitioning with BTRFS subvolumes.

## Disk Layout

| Partition | Size | Type | Mount |
|-----------|------|------|-------|
| ESP | 512MB | EFI (vfat) | `/boot` |
| root | Rest | BTRFS | Subvolumes |

### BTRFS Subvolumes

| Subvolume | Mount | Purpose |
|-----------|-------|---------|
| `@` | `/` | Root filesystem |
| `@home` | `/home` | User data |
| `@nix` | `/nix` | Nix store |
| `@var` | `/var` | Variable data |
| `@swap` | `/swap` | Swapfile (34GB for hibernation) |
| `@snapshots` | `/.snapshots` | BTRFS snapshots |

All subvolumes use `compress=zstd` and `noatime` for optimal performance.

## Prerequisites

- NixOS installation ISO (minimal or graphical)
- USB stick for the installer
- Network connection (Ethernet recommended)
- This flake repository

## Installation Steps

### 1. Boot from NixOS Installer

Download the latest NixOS ISO and create a bootable USB:
```bash
# On an existing Linux system
sudo dd if=nixos-minimal-*.iso of=/dev/sdX bs=4M status=progress
```

Boot the target PC from the USB stick.

### 2. Connect to Network

```bash
# For WiFi
sudo systemctl start wpa_supplicant
wpa_cli
> add_network
> set_network 0 ssid "YourSSID"
> set_network 0 psk "YourPassword"
> enable_network 0
> quit

# Verify connection
ping -c 3 nixos.org
```

### 3. Clone the Configuration Repository

```bash
nix-shell -p git

# Clone to /tmp (installer has limited space)
git clone https://github.com/YOUR_USERNAME/nixos-config.git /tmp/nixos-config
cd /tmp/nixos-config
```

### 4. Verify Target Disk

**IMPORTANT: This will erase all data on the disk!**

```bash
# List disks
lsblk

# Verify /dev/nvme0n1 is the correct 1TB NVMe SSD
# If different, edit hosts/samuels-pc/disko.nix accordingly
```

### 5. Run Disko to Partition and Format

```bash
sudo nix --experimental-features "nix-command flakes" run github:nix-community/disko -- \
  --mode disko \
  /tmp/nixos-config/hosts/samuels-pc/disko.nix
```

This will:
- Create GPT partition table
- Create EFI and root partitions
- Format with BTRFS
- Create all subvolumes
- Mount everything to `/mnt`

### 6. Verify Mounts

```bash
mount | grep /mnt
# Should show:
# /dev/nvme0n1p2 on /mnt type btrfs (subvol=/@,compress=zstd,noatime)
# /dev/nvme0n1p2 on /mnt/home type btrfs (subvol=/@home,compress=zstd,noatime)
# /dev/nvme0n1p2 on /mnt/nix type btrfs (subvol=/@nix,compress=zstd,noatime)
# ...
```

### 7. Generate Hardware Configuration (Optional)

If you want to capture specific hardware details:
```bash
nixos-generate-config --root /mnt --show-hardware-config
# Review output and update hosts/samuels-pc/hardware-configuration.nix if needed
```

### 8. Install NixOS

```bash
sudo nixos-install --flake /tmp/nixos-config#samuels-pc --no-root-passwd
```

During installation:
- The system will be built from the flake
- No root password prompt (user has sudo via wheel group)

### 9. Set User Password

```bash
# After install, before reboot
sudo nixos-enter --root /mnt
passwd samuel
exit
```

### 10. Reboot

```bash
sudo reboot
```

Remove the USB stick when prompted.

## Post-Installation

### Update Hardware Configuration

After first boot, review and update hardware-specific settings:

```bash
# Check CPU type and enable microcode
# In hosts/samuels-pc/hardware-configuration.nix:
# - For Intel: hardware.cpu.intel.updateMicrocode = true;
# - For AMD: hardware.cpu.amd.updateMicrocode = true;

# Check GPU and enable drivers if needed
lspci | grep -i vga
```

### Rebuild System

```bash
cd ~/repos/nixos-config  # or wherever you clone it
sudo nixos-rebuild switch --flake .#samuels-pc
```

### Verify BTRFS Setup

```bash
# List subvolumes
sudo btrfs subvolume list /

# Check filesystem usage
sudo btrfs filesystem usage /

# Check compression ratio
sudo compsize /
```

## BTRFS Maintenance

### Create Snapshots

```bash
# Snapshot root
sudo btrfs subvolume snapshot -r / /.snapshots/root-$(date +%Y%m%d)

# Snapshot home
sudo btrfs subvolume snapshot -r /home /.snapshots/home-$(date +%Y%m%d)
```

### Restore from Snapshot

```bash
# Boot from USB, mount BTRFS partition
mount /dev/nvme0n1p2 /mnt

# Delete broken subvolume
btrfs subvolume delete /mnt/@

# Restore from snapshot
btrfs subvolume snapshot /mnt/@snapshots/root-YYYYMMDD /mnt/@
```

### Scrub (Monthly)

```bash
sudo btrfs scrub start /
sudo btrfs scrub status /
```

## Troubleshooting

### "Device not found" during disko

Verify the device path in `disko.nix`:
```bash
ls -la /dev/nvme*
# Update disko.nix if device is different (e.g., /dev/nvme1n1)
```

### Boot fails after install

1. Boot from USB
2. Mount manually:
   ```bash
   mount -o subvol=@ /dev/nvme0n1p2 /mnt
   mount -o subvol=@nix /dev/nvme0n1p2 /mnt/nix
   mount /dev/nvme0n1p1 /mnt/boot
   ```
3. Chroot and fix:
   ```bash
   nixos-enter --root /mnt
   ```

### Swapfile not working

BTRFS swapfiles need special handling. Verify in disko.nix that the `@swap` subvolume doesn't have compression (disko handles this automatically).

## References

- [Disko GitHub](https://github.com/nix-community/disko)
- [NixOS Wiki: Btrfs](https://wiki.nixos.org/wiki/Btrfs)
- [Disko BTRFS Examples](https://github.com/nix-community/disko/blob/master/example/btrfs-subvolumes.nix)
