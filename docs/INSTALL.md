# NixOS Installation

## Quick Install

```bash
# 1. Boot NixOS ISO

# 2. Clone and run installer
nix-env -iA nixos.git
git clone https://github.com/oechsler/nix.git /tmp/nix
cd /tmp/nix
./install.sh -h samuels-razer

# 3. Reboot
reboot
```

The installer prompts interactively for:
- LUKS disk encryption password
- SSH private key (paste it)
- Username for SSH/sops setup

Use `-y` to skip disk wipe confirmation, `-s /path/to/key` to provide SSH key as file.

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
