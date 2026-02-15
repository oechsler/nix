# NixOS Installation

## Quick Install

```bash
# 1. Boot NixOS ISO

# 2. Set LUKS password
echo "your-secure-password" > /tmp/luks-password

# 3. Clone and run installer
nix-env -iA nixos.git
git clone https://github.com/oechsler/nix.git /tmp/nix
cd /tmp/nix
./install.sh -h samuels-razer -s /path/to/ssh-key -y

# 4. Reboot
reboot
```

## Manual Install

If the install script doesn't work:

```bash
# 1. Set LUKS password
echo "your-secure-password" > /tmp/luks-password

# 2. Run disko
export NIX_CONFIG="experimental-features = nix-command flakes"
nix run github:nix-community/disko -- --mode destroy,format,mount --flake /tmp/nix#HOST

# 3. Generate hardware config
nixos-generate-config --root /mnt --show-hardware-config > /tmp/nix/hosts/HOST/hardware-configuration.generated.nix

# 4. Install
nixos-install --flake /tmp/nix#HOST --no-root-password

# 5. Copy SSH key and sops age key
mkdir -p /mnt/home/samuel/.ssh
cp /path/to/ssh-key /mnt/home/samuel/.ssh/id_ed25519
ssh-keygen -y -f /mnt/home/samuel/.ssh/id_ed25519 > /mnt/home/samuel/.ssh/id_ed25519.pub

mkdir -p /mnt/var/lib/sops/age
nix-shell -p ssh-to-age --run "ssh-to-age -private-key -i /path/to/ssh-key" > /mnt/var/lib/sops/age/keys.txt

# 6. Fix permissions
nixos-enter --root /mnt -c "chown -R samuel:users /home/samuel"
chmod 600 /mnt/home/samuel/.ssh/id_ed25519
chmod 600 /mnt/var/lib/sops/age/keys.txt

# 7. Reboot
reboot
```

## Disk Layout

Both hosts use LUKS full disk encryption with btrfs subvolumes:

```
/dev/nvme...
├── BOOT (512M, FAT32, /boot) - unencrypted EFI partition
└── root (rest)
    └── LUKS (cryptroot)
        └── btrfs (label: nixos)
            ├── @          → /
            ├── @home      → /home
            ├── @nix       → /nix
            ├── @persist   → /persist (survives root wipe)
            └── @snapshots → /.snapshots
```

samuels-pc has an additional encrypted games disk:
```
/dev/nvme... (second disk)
└── games
    └── LUKS (cryptgames)
        └── btrfs (label: games)
            └── @games → /mnt/games
```

## Impermanence

Root (`@`) is wiped on every boot. Persistent data goes in `/persist`:
- `/var/lib/bluetooth`
- `/var/lib/docker`
- `/var/lib/NetworkManager`
- `/var/lib/nixos`
- `/var/lib/sops`
- etc.

User password is declarative in `modules/system/users.nix`.

## SOPS Secrets

Secrets (WiFi, SMB credentials) are encrypted with age. The age key is derived from your SSH key.

After install, verify sops works:
```bash
cd ~/repos/nix
./sops/decrypt.sh  # should create sops.decrypted.yaml
```

## Troubleshooting

### Boot fails
```bash
# Boot from USB, unlock and mount:
cryptsetup open /dev/disk/by-partlabel/disk-main-root cryptroot
mount -o subvol=@ /dev/mapper/cryptroot /mnt
mount -o subvol=@nix /dev/mapper/cryptroot /mnt/nix
mount /dev/disk/by-label/BOOT /mnt/boot
nixos-enter --root /mnt
```

### Forgot LUKS password
You need to reinstall. Keep backups in `/persist` or external storage.

## TPM Unlock (Optional, Future)

After setting up Secure Boot with lanzaboote, you can add TPM-based auto-unlock:

```bash
# Enroll TPM (keeps password as fallback)
sudo systemd-cryptenroll /dev/disk/by-partlabel/disk-main-root --tpm2-device=auto --tpm2-pcrs=0+7

# Test: reboot should auto-unlock
```

This binds the LUKS key to your TPM - disk auto-unlocks in your PC but is useless if stolen.
