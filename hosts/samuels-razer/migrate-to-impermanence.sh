#!/usr/bin/env bash
set -euo pipefail

# Migration script for impermanence on existing installation
# Run this ONCE before enabling impermanence.enable = true

if [[ $EUID -ne 0 ]]; then
  echo "This script must be run as root"
  exit 1
fi

DISK="/dev/disk/by-label/nixos"

echo "=== Creating @persist subvolume ==="
mount -t btrfs -o subvol=/ "$DISK" /mnt
if btrfs subvolume show /mnt/@persist &>/dev/null; then
  echo "@persist already exists, skipping creation"
else
  btrfs subvolume create /mnt/@persist
  echo "Created @persist subvolume"
fi
umount /mnt

echo "=== Mounting @persist ==="
mkdir -p /persist
mount -t btrfs -o subvol=@persist,compress=zstd,noatime "$DISK" /persist

echo "=== Creating directory structure ==="
mkdir -p /persist/var/lib/systemd
mkdir -p /persist/etc/ssh

echo "=== Migrating data ==="

migrate_dir() {
  local src="$1"
  local dst="$2"
  if [[ -d "$src" ]]; then
    echo "  $src -> $dst"
    cp -a "$src" "$dst"
  else
    echo "  $src (not found, skipping)"
  fi
}

migrate_file() {
  local src="$1"
  local dst="$2"
  if [[ -f "$src" ]]; then
    echo "  $src -> $dst"
    cp -a "$src" "$dst"
  else
    echo "  $src (not found, skipping)"
  fi
}

# /var/lib directories
migrate_dir /var/lib/bluetooth /persist/var/lib/
migrate_dir /var/lib/docker /persist/var/lib/
migrate_dir /var/lib/flatpak /persist/var/lib/
migrate_dir /var/lib/NetworkManager /persist/var/lib/
migrate_dir /var/lib/nixos /persist/var/lib/
migrate_dir /var/lib/sddm /persist/var/lib/
migrate_dir /var/lib/sops /persist/var/lib/
migrate_dir /var/lib/tailscale /persist/var/lib/

# /var/lib/systemd subdirectories
migrate_dir /var/lib/systemd/rfkill /persist/var/lib/systemd/
migrate_dir /var/lib/systemd/timers /persist/var/lib/systemd/
migrate_dir /var/lib/systemd/coredump /persist/var/lib/systemd/
migrate_file /var/lib/systemd/random-seed /persist/var/lib/systemd/

# /etc files
migrate_file /etc/machine-id /persist/etc/
migrate_file /etc/ssh/ssh_host_ed25519_key /persist/etc/ssh/
migrate_file /etc/ssh/ssh_host_ed25519_key.pub /persist/etc/ssh/
migrate_file /etc/ssh/ssh_host_rsa_key /persist/etc/ssh/
migrate_file /etc/ssh/ssh_host_rsa_key.pub /persist/etc/ssh/

echo "=== Done ==="
echo ""
echo "Next steps:"
echo "1. Add 'impermanence.enable = true;' to your host configuration"
echo "2. Run 'sudo nixos-rebuild switch --flake .'"
echo "3. Reboot and verify everything works"
echo ""
echo "After reboot, your root filesystem will be wiped on every boot!"
