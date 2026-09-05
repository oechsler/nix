# NixOS Installation

This guide covers installing a host from the repository's interactive installer,
the prebuilt graphical ISO, or the installer script directly. It also explains
the storage layout and the post-install steps required for security features.

## Choose an Installation Path

- [Interactive installer](#interactive-installer): recommended for most installations.
- [Graphical offline ISO](#graphical-offline-iso): use when the target should install from prebuilt closures.
- [Manual install](#manual-install): run the installer from a cloned checkout.

All paths read the selected host's feature flags and use the same disk layout.

## Interactive Installer

Boot the NixOS ISO and run:

```bash
curl -sL https://oech.it/u/bmxl3a | sudo bash
```

This clones the repo and launches the interactive installer. It will:

1. Show available hosts and let you pick one
2. Read the host's config to detect enabled features
3. Prompt only for what's needed (LUKS password, SSH key)
4. Partition, install, and set up post-install (SSH, SOPS, TOTP)

> **Note:** YubiKey enrollment (both LUKS and PAM) is **not done during install** — it must be run after first boot using `sudo yubikey-luks-init` and `sudo yubikey-init`. The installer shows you exactly which commands to run at the end.

## Graphical Offline ISO

Build the graphical ISO on a machine with enough RAM:

```bash
./build-iso.sh
```

The ISO build output is linked as `result/`; the bootable image is inside `result/iso/`. It contains the prebuilt closures for every host directory in `hosts/`. Boot the ISO, open Konsole, and start the installer explicitly:

```bash
/etc/nixos-installer/install.sh
```

The ISO includes the required system files, so the target machine does not need to compile the system during installation.

CLI flags are passed through to `install.sh`:

```bash
# Re-run only post-install (e.g. after failed TOTP setup)
curl -sL https://oech.it/u/bmxl3a | sudo bash -s -- --post-install --host HOST -s /path/to/key
```

To test a different branch:

```bash
BRANCH=dev curl -sL https://oech.it/u/bmxl3a | sudo bash
```

### Manual Install

```bash
nix-env -iA nixos.git
git clone https://github.com/oechsler/nix.git /tmp/nix-config
/tmp/nix-config/install.sh
```

### CLI Options

```
./install.sh                              # Full install (all steps)
./install.sh --host samuels-terra         # Pre-select host
./install.sh --host HOST -s KEY -p PWD -y # Fully automated
./install.sh --install --post-install     # Reinstall without formatting
./install.sh --post-install               # Re-run post-install only
./install.sh --hardware-config --host HOST # Generate hardware config only
./install.sh --dry-run                    # Show summary and exit
./install.sh -h                           # Show help
```

| Flag                             | Description                                                   |
| -------------------------------- | ------------------------------------------------------------- |
| `--host HOST`                    | Pre-select host (skip menu)                                   |
| `-s`, `--ssh-key FILE`           | SSH private key path                                          |
| `-p`, `--luks-password PASSWORD` | LUKS disk encryption password                                 |
| `--iso`                          | Use the prebuilt closure and manifest from the installer ISO  |
| `--format`                       | Partition and format disks (disko)                            |
| `--install`                      | Install NixOS (nixos-install)                                 |
| `--post-install`                 | Post-install setup (SSH, SOPS, TOTP, YubiKey, TPM/FIDO2)      |
| `--hardware-config`              | Generate hardware configuration for the selected host         |
| `--skip-totp`                    | Skip TOTP setup for this run                                  |
| `--quiet`                        | Suppress upgrade prompts on installed systems                 |
| `--repair`                       | Verify/repair the Nix store before an upgrade                 |
| `-y`, `--yes`                    | Skip confirmation (requires `-s`, `-p` if encryption enabled) |
| `--dry-run`                      | Show summary and exit without making changes                  |
| `-h`, `--help`                   | Show help                                                     |

Steps are combinable. Without step flags, the full install runs. `--hardware-config` is standalone and only generates the selected host's hardware configuration. The installer reads host feature flags from the local flake or, in ISO mode, from the embedded manifest.

## Disk Layout

The base layout consists of an unencrypted EFI system partition and one
LUKS-encrypted Btrfs partition. The host's Disko definition creates the core
volumes below and may include additional feature-specific data subvolumes.

```
/dev/nvme...                                            # Physical disk
├── BOOT (512 MiB, FAT32)                               # EFI system partition
│   └── /boot                                           #
└── root (remaining space)                              # Main data partition
    └── cryptroot                                       # LUKS2 mapping
        └── nixos                                       # Btrfs filesystem
            ├── @                                       # Root filesystem
            │   └── /                                   #
            ├── @home                                   # User data
            │   └── /home                               #
            ├── @nix                                    # Nix store
            │   └── /nix                                #
            ├── @persist                                # Persistent system state
            │   └── /persist                            #
            └── ...                                      # Optional feature volumes
```

Optional data subvolumes are only used when their feature is enabled. Whether
they are physically created is controlled by the selected host's Disko file.

| Subvolume    | Mountpoint                        | Required feature                  |
| ------------ | --------------------------------- | --------------------------------- |
| `@snapshots` | `/.snapshots`                     | `features.snapshots.enable`       |
| `@steam`     | `/home/<user>/.local/share/Steam` | `features.gaming.enable`          |
| `@nextcloud` | `/home/<user>/Nextcloud`          | `features.apps.nextcloud.enable`  |
| `@smb`       | `/home/<user>/smb`                | `features.smb.enable` with shares |

When impermanence is enabled, `@` is reset on boot while `/home`, `/nix`, and
`/persist` retain their declared state. Optional data subvolumes keep large or
independently managed data outside `@home` snapshots. The Btrfs top-level is
also mounted at `/mnt/btrfs-root` as a convenience view of all subvolumes.
`btrbk` uses this view for snapshot operations, while `/.snapshots` remains the
normal path for browsing snapshots.

## Post-Install State

### Impermanence

When `features.impermanence.enable = true`, root (`@`) is wiped on every boot.
Persistent data goes in `/persist`.

When Impermanence is disabled, the root filesystem and its state remain
persistent across reboots as usual.

You only need the separate `/var` storage when Impermanence is disabled. With
Impermanence enabled, `/var` is reset together with the root filesystem and
only the system data needed across boots is kept under `/persist`.

Always-persistent core state:

- `/var/lib/NetworkManager`
- `/var/lib/backgrounds` (prepared wallpapers and blur cache)
- `/var/lib/nixos`
- `/var/lib/power-profiles-daemon`
- `/var/lib/sops`
- `/var/lib/systemd`

Feature-dependent state:

- `/var/lib/bluetooth` (Bluetooth)
- `/var/lib/containers` and `/var/lib/docker` (containers)
- `/etc/libvirt` and `/var/lib/libvirt` (virtual machines)
- `/var/lib/flatpak` (Flatpak)
- `/var/lib/iwd` (WiFi)
- `/var/lib/ollama` (Ollama models and server state)
- `/var/lib/pam-lldap` (LDAP authentication)
- `/var/lib/sbctl` (Secure Boot)
- `/var/lib/sddm` (desktop login)
- `/var/lib/tailscale` (Tailscale)
- `/persist/etc/ssh/*` (SSH host keys)

Only state required by enabled features is kept automatically. Additional paths
can be configured through `features.impermanence.extraPaths`.

### SOPS Secrets

Secrets are encrypted with SOPS and age. The repository uses an Age identity
derived from the user's SSH key; see [sops/README.md](../sops/README.md).

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

Recovery depends on the available LUKS slots, recovery keys, and backups. A
reinstall is only necessary if no valid unlock method remains.

## Secure Boot Setup

Secure Boot is disabled by default. To enable it:

### 1. Enable in config

In your host's `configuration.nix`:

```nix
features = {
  secureBoot.enable = true;
};
```

### 2. Run `secure-boot-init` after first boot

The installer skips Secure Boot key enrollment (keys don't exist yet at install time). After the first normal boot, run:

```bash
sudo secure-boot-init
```

The script auto-detects your board and guides you through the correct steps. It handles everything: generating keys, signing boot files, enrolling into firmware.

### Standard boards

**Step A** — In UEFI: enter Setup Mode:

1. Disable Secure Boot
2. Enable **Setup Mode** (sometimes called "Reset to Setup Mode") — this clears existing keys
3. Save and reboot into NixOS

**Step B** — Run `secure-boot-init`:

```bash
sudo secure-boot-init
```

The script generates keys, rebuilds with lanzaboote active, and enrolls:

```bash
sbctl enroll-keys --microsoft --firmware-builtin
```

**Step C** — In UEFI: enable Secure Boot. Then run `sudo secure-boot-init` once more to verify all files are signed.

### ASUS boards (non-standard)

ASUS firmware incorrectly reports SetupMode=0 after key deletion. `secure-boot-init` detects ASUS boards and uses partial enrollment to bypass the SetupMode check.

**Step A** — In UEFI (Boot → Secure Boot): clear existing keys:

1. **OS Type:** Other OS
2. **Secure Boot Mode:** Custom
3. **Key Management:** Clear Secure Boot Keys
4. Save and reboot into NixOS

**Step B** — Run `secure-boot-init`:

```bash
sudo secure-boot-init
```

The script generates keys, rebuilds with lanzaboote active, and enrolls via partial enrollment:

```bash
sbctl enroll-keys --partial db  --microsoft --firmware-builtin --ignore-immutable --yes-this-might-brick-my-machine
sbctl enroll-keys --partial KEK --microsoft --firmware-builtin --ignore-immutable --yes-this-might-brick-my-machine
sbctl enroll-keys --partial PK  --ignore-immutable --yes-this-might-brick-my-machine
```

**Step C** — In UEFI: activate Secure Boot:

1. **OS Type:** Windows UEFI mode
2. **Secure Boot:** Enabled

Then run `sudo secure-boot-init` once more to verify all files are signed.

### Verify

```bash
sudo secure-boot-init
```

When Secure Boot is active and all keys are enrolled, `secure-boot-init` detects this automatically, runs `sbctl verify` to confirm all boot files are signed, and exits with a success message. No manual `bootctl status` needed.

### TPM + Secure Boot ordering

If you use TPM2 auto-unlock **and** Secure Boot, always enroll TPM **after** Secure Boot is fully active. PCR 7 seals against the Secure Boot state — enrolling before activation produces a seal that breaks once Secure Boot is turned on.

Until both steps are complete, unlock LUKS with the installation password:

```
1. sudo secure-boot-init   # activate Secure Boot first
2. sudo tpm-luks-init      # then enroll TPM
```

`secure-boot-init` and the installer both remind you of this ordering.

## LUKS Unlock

Three unlock methods are available. The active method is set per host via `features.encryption.unlockMethod`:

| Method           | Feature flag                      | Boot experience                     |
| ---------------- | --------------------------------- | ----------------------------------- |
| TPM2 auto-unlock | `unlockMethod = "tpm2"` (default) | Fully automatic (sealed to PCR 0+7) |
| YubiKey FIDO2    | `unlockMethod = "yubikey"`        | Plug in YubiKey + touch at boot     |
| Password         | `unlockMethod = "password"`       | Enter LUKS passphrase at boot       |

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
