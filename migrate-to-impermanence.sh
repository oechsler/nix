#!/usr/bin/env bash
# Migration script: Remove @var subvolume and set up impermanence
# Run this from a NixOS live USB

set -euo pipefail

MNT="/mnt/btrfs-root"
FLAKE_DIR="$(cd "$(dirname "$0")" && pwd)"
HOST="${1:-}"

if [[ -z "$HOST" ]]; then
  echo "Usage: $0 <hostname>"
  echo "  e.g. $0 samuels-pc"
  exit 1
fi

# Try to find the root disk by label first, fallback to common locations
if [[ -e "/dev/disk/by-partlabel/disk-main-root" ]]; then
  DISK="/dev/disk/by-partlabel/disk-main-root"
elif [[ -e "/dev/disk/by-label/nixos" ]]; then
  DISK="/dev/disk/by-label/nixos"
else
  echo "ERROR: Could not find root partition."
  echo "       Expected /dev/disk/by-partlabel/disk-main-root or /dev/disk/by-label/nixos"
  exit 1
fi

# Try to find ESP partition
if [[ -e "/dev/disk/by-partlabel/disk-main-ESP" ]]; then
  ESP="/dev/disk/by-partlabel/disk-main-ESP"
elif [[ -e "/dev/disk/by-label/boot" ]]; then
  ESP="/dev/disk/by-label/boot"
else
  # Fallback: assume first partition on same disk as root
  ROOT_DISK="$(lsblk -no PKNAME "$DISK" | head -1)"
  ESP="/dev/${ROOT_DISK}p1"
  if [[ ! -e "$ESP" ]]; then
    ESP="/dev/${ROOT_DISK}1"
  fi
  echo "WARNING: Using guessed ESP path: $ESP"
  echo "         If this is wrong, mount /mnt/boot manually before continuing."
fi

# Directories to persist (must match impermanence.nix)
PERSIST_DIRS=(
  "var/lib/bluetooth"
  "var/lib/docker"
  "var/lib/flatpak"
  "var/lib/NetworkManager"
  "var/lib/nixos"
  "var/lib/sddm"
  "var/lib/sops"
  "var/lib/tailscale"
  "var/lib/systemd/rfkill"
  "var/lib/systemd/timers"
  "var/lib/systemd/coredump"
)

echo "=== Impermanence Migration Script ==="
echo ""
echo "Host: $HOST"
echo "Root: $DISK"
echo "ESP:  $ESP"
echo "Flake: $FLAKE_DIR"
echo ""
echo "This script will:"
echo "  1. Copy important /var/lib/* data to @persist"
echo "  2. Delete the @var subvolume"
echo "  3. Install NixOS with the new config"
echo "  4. /var will now be part of @ and wiped on each boot"
echo ""
read -p "Continue? (y/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
  echo "Aborted."
  exit 1
fi

# Mount btrfs root
echo ""
echo "==> Mounting btrfs root..."
mkdir -p "$MNT"
mount -t btrfs -o subvol=/ "$DISK" "$MNT"

# Check subvolumes exist
if [[ ! -d "$MNT/@persist" ]]; then
  echo "ERROR: @persist subvolume not found."
  umount "$MNT"
  exit 1
fi

ALREADY_MIGRATED=false
if [[ ! -d "$MNT/@var" ]]; then
  echo "INFO: @var subvolume not found. Already migrated, skipping data copy."
  ALREADY_MIGRATED=true
fi

if [[ "$ALREADY_MIGRATED" == false ]]; then
  # Copy persistent directories from @var
  echo ""
  echo "==> Copying persistent directories to @persist..."
  for dir in "${PERSIST_DIRS[@]}"; do
    src="$MNT/@var/$dir"
    dest="$MNT/@persist/$dir"

    if [[ -d "$src" ]]; then
      echo "  Copying $dir..."
      mkdir -p "$(dirname "$dest")"
      cp -a "$src" "$dest"
    else
      echo "  Skipping $dir (not found)"
    fi
  done

  # Copy /etc files from @
  echo ""
  echo "==> Copying /etc files to @persist..."
  mkdir -p "$MNT/@persist/etc/ssh"

  if [[ -f "$MNT/@/etc/machine-id" ]]; then
    echo "  Copying etc/machine-id..."
    cp -a "$MNT/@/etc/machine-id" "$MNT/@persist/etc/"
  fi

  for key in ssh_host_ed25519_key ssh_host_ed25519_key.pub ssh_host_rsa_key ssh_host_rsa_key.pub; do
    if [[ -f "$MNT/@/etc/ssh/$key" ]]; then
      echo "  Copying etc/ssh/$key..."
      cp -a "$MNT/@/etc/ssh/$key" "$MNT/@persist/etc/ssh/"
    fi
  done

  # Delete @var subvolume
  echo ""
  echo "==> Deleting @var subvolume..."

  # First delete any nested subvolumes
  btrfs subvolume list -o "$MNT/@var" 2>/dev/null | cut -f9 -d' ' | while read subvol; do
    if [[ -n "$subvol" ]]; then
      echo "  Deleting nested subvolume: $subvol"
      btrfs subvolume delete "$MNT/$subvol"
    fi
  done

  btrfs subvolume delete "$MNT/@var"
fi

# Show result
echo ""
echo "==> Current subvolumes:"
btrfs subvolume list "$MNT"

# Unmount btrfs root
echo ""
echo "==> Unmounting btrfs root..."
umount "$MNT"

# Mount system for nixos-install
echo ""
echo "==> Mounting system for nixos-install..."
mount -t btrfs -o subvol=@,compress=zstd,noatime "$DISK" /mnt
mkdir -p /mnt/{home,nix,persist,boot,.snapshots}
mount -t btrfs -o subvol=@home,compress=zstd,noatime "$DISK" /mnt/home
mount -t btrfs -o subvol=@nix,compress=zstd,noatime "$DISK" /mnt/nix
mount -t btrfs -o subvol=@persist,compress=zstd,noatime "$DISK" /mnt/persist
mount -t btrfs -o subvol=@snapshots,compress=zstd,noatime "$DISK" /mnt/.snapshots
mount "$ESP" /mnt/boot

echo ""
echo "==> Installing NixOS..."
nixos-install --flake "$FLAKE_DIR#$HOST" --no-root-passwd

echo ""
echo "==> Unmounting..."
umount -R /mnt

echo ""
echo "=== Migration complete! ==="
echo ""
echo "You can now reboot into your system."
echo ""
