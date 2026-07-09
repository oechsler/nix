# NixOS Installation

## Quickstart

Boot the NixOS ISO and run:

```bash
curl -sL https://bin.at.oechsler.it/u/bmxl3a | sudo bash
```

This clones the repo and launches the interactive installer. It will:

1. Show available hosts and let you pick one
2. Read the host's config to detect enabled features
3. Prompt only for what's needed (LUKS password, SSH key)
4. Partition, install, and set up post-install (SSH, SOPS, TOTP)

> **Note:** YubiKey enrollment (both LUKS and PAM) is **not done during install** — it must be run after first boot using `sudo yubikey-luks-init` and `sudo yubikey-init`. The installer shows you exactly which commands to run at the end.

CLI flags are passed through to `install.sh`:

```bash
# Re-run only post-install (e.g. after failed TOTP setup)
curl -sL https://bin.at.oechsler.it/u/bmxl3a | sudo bash -s -- --post-install --host HOST -s /path/to/key
```

To test a different branch: `BRANCH=dev curl -sL ... | sudo bash`

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
| `--post-install` | Post-install setup (SSH, SOPS, TOTP, YubiKey, TPM/FIDO2) |
| `--host HOST` | Pre-select host (skip menu) |
| `-s`, `--ssh-key FILE` | SSH private key path |
| `-p`, `--luks-password PASSWORD` | LUKS disk encryption password |
| `-y`, `--yes` | Skip confirmation (requires `-s`, `-p` if encryption enabled) |
| `--dry-run` | Show summary and exit without making changes |
| `-h`, `--help` | Show help |

Steps are combinable. Without step flags, all three run. The installer reads host feature flags with `nix eval` and only asks relevant questions.

## Disk Layout

All hosts use LUKS full disk encryption with btrfs subvolumes:

```
/dev/nvme...
├── BOOT (512M, FAT32, /boot) - unencrypted EFI partition
└── root (rest)
    └── LUKS (cryptroot)
        └── btrfs (label: nixos)
            ├── @          → /              (ephemeral — wiped on boot when impermanence enabled)
            ├── @home      → /home          (permanent user data)
            ├── @nix       → /nix           (permanent Nix store)
            ├── @persist   → /persist       (permanent state — only with impermanence enabled)
            └── @snapshots → mounted at /mnt/btrfs-root/@snapshots by btrbk
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
- `/var/lib/NetworkManager`, `/var/lib/bluetooth`
- `/var/lib/docker`
- `/var/lib/nixos`, `/var/lib/sops`
- `/persist/etc/ssh/*` (SSH host keys)
- See `modules/system/impermanence.nix` for the full path list.

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

### 2. Run `secure-boot-init` after first boot

The installer skips Secure Boot key enrollment (keys don't exist yet at install time). After the first normal boot, run:

```bash
sudo secure-boot-init
```

The script auto-detects your board and guides you through the correct steps. It handles everything: generating keys, signing boot files, enrolling into firmware.

### Standard boards

Before running `secure-boot-init`, in UEFI:
1. Disable Secure Boot
2. Enable **Setup Mode** (clears existing keys — required for custom key enrollment)

The script then calls:
```bash
sbctl enroll-keys --microsoft   # keeps Windows/firmware compatibility
```

Then re-enable Secure Boot in UEFI.

### ASUS boards (non-standard)

ASUS firmware disables Secure Boot instead of entering Setup Mode when keys are cleared. Setting **Custom Mode** in UEFI allows enrollment without requiring Setup Mode — `secure-boot-init` detects ASUS boards and prompts for this automatically.

Before running `secure-boot-init`, in UEFI (Boot → Secure Boot):
- **OS Type:** Other OS
- **Secure Boot Mode:** Custom
- **Key Management:** leave keys untouched — do NOT clear them

The script then calls:
```bash
sbctl enroll-keys --microsoft
```

Afterwards, in UEFI: set OS Type → Windows UEFI mode, Secure Boot → On.

### Verify

```bash
sudo secure-boot-init
```

When Secure Boot is active and all keys are enrolled, `secure-boot-init` detects this automatically, runs `sbctl verify` to confirm all boot files are signed, and exits with a success message. No manual `bootctl status` needed.

### TPM + Secure Boot ordering

If you use TPM2 auto-unlock **and** Secure Boot, always enroll TPM **after** Secure Boot is fully active. PCR 7 seals against the Secure Boot state — enrolling before activation produces a seal that breaks once Secure Boot is turned on.

```
1. sudo secure-boot-init   # activate Secure Boot first
2. sudo tpm-luks-init      # then enroll TPM
```

`secure-boot-init` and the installer both remind you of this ordering.

## LUKS Unlock

Three unlock methods are available. The active method is set per host via `features.encryption.unlockMethod`:

| Method | Feature flag | Boot experience |
|--------|-------------|-----------------|
| TPM2 auto-unlock | `unlockMethod = "tpm2"` (default) | Fully automatic (sealed to PCR 0+7) |
| YubiKey FIDO2 | `unlockMethod = "yubikey"` | Plug in YubiKey + touch at boot |
| Password | `unlockMethod = "password"` | Enter LUKS passphrase at boot |

Password always remains as a fallback (slot 0 is never touched).

### YubiKey FIDO2

```bash
sudo yubikey-luks-init   # choose "enroll"
```

Enrolls all LUKS partitions. At every boot: plug in the YubiKey and touch it when prompted. See [AUTH.md](AUTH.md#yubikey-fido2-luks-unlock) for switching between TPM and YubiKey.

### TPM2 Auto-Unlock

TPM seals the key to PCR 0+7 (firmware + Secure Boot state). If Secure Boot is enabled later, re-enroll:

```bash
sudo tpm-luks-init   # choose "enroll"
```

### Remove

```bash
sudo tpm-luks-init       # choose "wipe" (TPM)
sudo yubikey-luks-init   # choose "wipe" (FIDO2)
```

### Manual Reference

```bash
# List enrolled key slots
sudo systemd-cryptenroll /dev/disk/by-partlabel/disk-main-root

# Enroll TPM2 manually
sudo systemd-cryptenroll /dev/disk/by-partlabel/disk-main-root --tpm2-device=auto --tpm2-pcrs=0+7

# Enroll FIDO2 manually
sudo systemd-cryptenroll /dev/disk/by-partlabel/disk-main-root --fido2-device=auto

# Remove a slot manually
sudo systemd-cryptenroll /dev/disk/by-partlabel/disk-main-root --wipe-slot=tpm2
sudo systemd-cryptenroll /dev/disk/by-partlabel/disk-main-root --wipe-slot=fido2
```
