# NixOS Installation Guide

General installation guide for all hosts using disko with BTRFS subvolumes.

## Quick Install

```bash
# 1. Boot NixOS ISO (minimal or graphical)

# 2. Enable flakes
export NIX_CONFIG="experimental-features = nix-command flakes"

# 3. Clone config
nix-env -iA nixos.git
git clone <repo-url> /tmp/nix

# 4. Verify disk IDs match disko.nix (WILL ERASE ALL DATA!)
ls -l /dev/disk/by-id/nvme-*

# 5. Run disko (replace HOST with samuels-pc or samuels-razer)
nix run github:nix-community/disko -- --mode destroy,format,mount --flake /tmp/nix#HOST

# 6. Generate hardware config (remove fileSystems + swapDevices, disko handles mounts)
nixos-generate-config --root /mnt --show-hardware-config > /tmp/nix/hosts/HOST/hardware-configuration.nix

# 7. Install
sudo nixos-install --flake /tmp/nix#HOST

# 8. Set user password
nixos-enter --root /mnt -c 'passwd samuel'

# 9. Reboot
reboot
```

## SOPS Secrets Setup (Important!)

This config uses SOPS for secrets (WiFi, SMB, kubeconfig). The Age key is derived from your SSH key.

### Option A: Restore SSH key from backup (recommended)

```bash
mkdir -p ~/.ssh
cp /path/to/backup/id_ed25519 ~/.ssh/
cp /path/to/backup/id_ed25519.pub ~/.ssh/
chmod 600 ~/.ssh/id_ed25519

cd ~/nix
./sops/setup.sh
./sops/decrypt.sh  # verify it works
```

### Option B: New SSH key (requires re-encrypting)

```bash
ssh-keygen -t ed25519 -C "your-email@example.com"
cd ~/nix
./sops/setup.sh

# Edit sops/sops.decrypted.yaml with your secrets, then:
./sops/encrypt.sh
```

### Option C: Boot without secrets first

Comment out in `configuration.nix` for initial boot:
```nix
# ../../modules/system/networking.nix  # WiFi profiles
# ../../modules/system/smb.nix         # SMB mounts
```
Then restore SSH key, run `setup.sh`, uncomment, rebuild.

## Post-Install

```bash
# Clone to permanent location
git clone https://github.com/oechsler/nix.git ~/nix
cd ~/nix

# Setup SOPS (see above)
./sops/setup.sh

# Future rebuilds
sudo nixos-rebuild switch --flake .#HOST
```

## BTRFS Maintenance

```bash
# Snapshots
sudo btrfs subvolume snapshot -r / /.snapshots/root-$(date +%Y%m%d)
sudo btrfs subvolume snapshot -r /home /.snapshots/home-$(date +%Y%m%d)

# Monthly scrub
sudo btrfs scrub start /

# Check compression
sudo compsize /
```

## Troubleshooting

### Boot fails
```bash
# Boot from USB, mount manually:
mount -o subvol=@ /dev/disk/by-label/nixos /mnt
mount -o subvol=@nix /dev/disk/by-label/nixos /mnt/nix
mount /dev/disk/by-label/BOOT /mnt/boot
nixos-enter --root /mnt
```

### Restore from snapshot
```bash
mount /dev/disk/by-label/nixos /mnt
btrfs subvolume delete /mnt/@
btrfs subvolume snapshot /mnt/@snapshots/root-YYYYMMDD /mnt/@
```

## Backup Before Reinstall

```bash
cp -r ~/.ssh /path/to/backup/
cp -r ~/.gnupg /path/to/backup/
cp -r ~/.config/sops /path/to/backup/
cp -r ~/Nextcloud /path/to/backup/  # if applicable
```

## BTRFS Disk Layout

All hosts use the same subvolume structure:

| Subvolume | Mount | Options |
|-----------|-------|---------|
| `@` | `/` | compress=zstd, noatime |
| `@home` | `/home` | compress=zstd, noatime |
| `@nix` | `/nix` | compress=zstd, noatime |
| `@var` | `/var` | compress=zstd, noatime |
| `@swap` | `/swap` | swapfile (RAM + 2GB) |
| `@snapshots` | `/.snapshots` | for backups |

## Generate Hardware Configuration

For a new machine or to update hardware detection:

```bash
# During install (after disko, before nixos-install)
nixos-generate-config --root /mnt --show-hardware-config

# On running system
nixos-generate-config --show-hardware-config
```

Review the output and update `hosts/HOST/hardware-configuration.nix`:
- Kernel modules for your hardware
- Filesystem UUIDs (if not using disko)
- CPU type detection

## Hardware Notes

After install, check `hardware-configuration.nix`:

```nix
# CPU microcode (uncomment appropriate one)
hardware.cpu.intel.updateMicrocode = true;
# hardware.cpu.amd.updateMicrocode = true;

# GPU drivers if needed
# services.xserver.videoDrivers = [ "nvidia" ];
```

## Secure Boot (Optional)

For dual-boot with Windows or if Secure Boot is required:

1. Disable Secure Boot in UEFI (put in "Setup Mode")

2. Add to `configuration.nix`:
   ```nix
   imports = [ ../../modules/system/secure-boot.nix ];
   ```

3. Generate and enroll keys:
   ```bash
   sudo sbctl create-keys
   sudo nixos-rebuild switch --flake .#HOST
   sudo sbctl verify  # all should show ✓ Signed
   sudo sbctl enroll-keys --microsoft
   ```

4. Enable Secure Boot in UEFI, verify with `bootctl status`
