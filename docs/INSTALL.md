# NixOS Installation

## Quickstart

Boot the NixOS ISO (you're root by default) and run:

```bash
curl -sL https://raw.githubusercontent.com/oechsler/nix/main/quickstart.sh | bash
```

This clones the repo and launches the interactive installer. It will:

1. Show available hosts and let you pick one
2. Read the host's config to detect enabled features
3. Prompt only for what's needed (LUKS password, SSH key)
4. Partition, install, and set up post-install (SSH, SOPS, TOTP, YubiKey)

CLI flags are passed through to `install.sh`:

```bash
# Re-run only post-install (e.g. after failed TOTP setup)
curl -sL https://raw.githubusercontent.com/oechsler/nix/main/quickstart.sh | bash -s -- --post-install --host HOST -s /path/to/key
```

To test a different branch: `BRANCH=dev curl -sL ... | bash`

### Manual Install

```bash
nix-env -iA nixos.git
git clone https://github.com/oechsler/nix.git /tmp/nix-config
/tmp/nix-config/install.sh
```

### CLI Options

```
./install.sh                              # Full install (all steps)
./install.sh --host mythinkpad            # Pre-select host
./install.sh --host HOST -s KEY -p PWD -y # Fully automated
./install.sh --install --post-install     # Reinstall without formatting
./install.sh --post-install               # Re-run post-install only
./install.sh --dry-run                    # Show summary and exit
./install.sh -h                           # Show help
```

| Flag | Description |
|------|-------------|
| `--format` | Partition and format disks (disko) |
| `--install` | Install NixOS (nixos-install) |
| `--post-install` | Post-install setup (SSH, SOPS, TOTP, YubiKey, TPM) |
| `--host HOST` | Pre-select host (skip menu) |
| `-s`, `--ssh-key FILE` | SSH private key path |
| `-p`, `--luks-password PASSWORD` | LUKS disk encryption password |
| `-y`, `--yes` | Skip confirmation (requires `-s`, `-p` if encryption enabled) |
| `--dry-run` | Show summary and exit without making changes |
| `-h`, `--help` | Show help |

Steps are combinable. If none specified, all three run. The installer reads each host's configuration via `nix eval` to determine which features are enabled (encryption, impermanence, TOTP, etc.) and only asks relevant questions.

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
- `/var/lib/NetworkManager`, `/var/lib/bluetooth`
- `/var/lib/docker`, `/var/lib/waydroid`
- `/var/lib/nixos`, `/var/lib/sops`
- `/persist/etc/ssh/*` (SSH host keys)
- etc. (see `modules/system/impermanence.nix` for full list)

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

TPM-based auto-unlock for LUKS-encrypted disks. Works with or without Secure Boot.
PCR 0+7 seals to firmware + Secure Boot state. If Secure Boot is enabled later,
re-run `tpm-init` to re-enroll.

### Setup

```bash
sudo tpm-init
```

Enrolls all LUKS partitions automatically. The password stays as fallback.

### Remove

```bash
sudo tpm-init   # Choose "wipe"
```

### Manual Reference

```bash
# List enrolled key slots
sudo systemd-cryptenroll /dev/disk/by-partlabel/disk-main-root

# Enroll single device manually
sudo systemd-cryptenroll /dev/disk/by-partlabel/disk-main-root --tpm2-device=auto --tpm2-pcrs=0+7

# Remove TPM slot manually
sudo systemd-cryptenroll /dev/disk/by-partlabel/disk-main-root --wipe-slot=tpm2
```
