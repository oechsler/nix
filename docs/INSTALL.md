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

> **⚠️ Optional Feature**: Impermanence is enabled by default but can be disabled with `features.impermanence.enable = false;`.
>
> **Requires**: BTRFS filesystem with `@` and `@persist` subvolumes.

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

## Secure Boot Setup

Secure Boot is disabled by default. To enable it:

### 1. Enable in config

In your host's `configuration.nix`:
```nix
features.secureBoot.enable = true;
```

### 2. Prepare UEFI

Boot into UEFI/BIOS and:
- Disable Secure Boot
- Enable "Setup Mode" (or clear existing keys)

### 3. Generate and enroll keys

```bash
# Rebuild with lanzaboote enabled
sudo nixos-rebuild switch --flake .#hostname

# Create signing keys
sudo sbctl create-keys

# Rebuild again to sign boot files
sudo nixos-rebuild switch --flake .#hostname

# Verify all files are signed
sudo sbctl verify

# Enroll keys (--microsoft keeps Windows/firmware compatibility)
sudo sbctl enroll-keys --microsoft
```

### 4. Enable Secure Boot

Reboot into UEFI/BIOS, enable Secure Boot, then boot normally.

```bash
# Verify it's working
bootctl status
```

Should show "Secure Boot: enabled".

## TPM Unlock (Optional)

After setting up Secure Boot with lanzaboote, you can add TPM-based auto-unlock.

### Single Disk (samuels-razer)

```bash
# Enroll TPM for root disk (keeps password as fallback)
sudo systemd-cryptenroll /dev/disk/by-partlabel/disk-main-root --tpm2-device=auto --tpm2-pcrs=0+7
```

### Multiple Disks (samuels-pc)

Each LUKS-encrypted disk needs its own TPM enrollment:

```bash
# Enroll root disk
sudo systemd-cryptenroll /dev/disk/by-partlabel/disk-main-root --tpm2-device=auto --tpm2-pcrs=0+7

# Enroll games disk
sudo systemd-cryptenroll /dev/disk/by-partlabel/disk-games-games --tpm2-device=auto --tpm2-pcrs=0+7
```

Both disks will auto-unlock on boot. The password stays as fallback for each disk.

### Verify and Test

```bash
# List enrolled key slots for each disk
sudo systemd-cryptenroll /dev/disk/by-partlabel/disk-main-root
sudo systemd-cryptenroll /dev/disk/by-partlabel/disk-games-games

# Reboot to test auto-unlock
```

This binds LUKS keys to your TPM - disks auto-unlock in your PC but are useless if stolen.

### Remove TPM Enrollment

To remove TPM auto-unlock and go back to password-only:

```bash
# Remove TPM slot from root disk
sudo systemd-cryptenroll /dev/disk/by-partlabel/disk-main-root --wipe-slot=tpm2

# Remove TPM slot from games disk (samuels-pc only)
sudo systemd-cryptenroll /dev/disk/by-partlabel/disk-games-games --wipe-slot=tpm2
```

The password slot remains intact.
