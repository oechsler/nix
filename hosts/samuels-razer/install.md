# NixOS Installation Guide for samuels-razer

Reinstallation guide for the Razer laptop with BTRFS.

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
| `@swap` | `/swap` | Swapfile (18GB for hibernation) |
| `@snapshots` | `/.snapshots` | BTRFS snapshots |

## Quick Install

```bash
# 1. Boot NixOS ISO

# 2. Connect to WiFi
sudo systemctl start wpa_supplicant
wpa_cli
> add_network
> set_network 0 ssid "YourSSID"
> set_network 0 psk "YourPassword"
> enable_network 0
> quit

# 3. Clone config
nix-shell -p git
git clone https://github.com/YOUR_USERNAME/nixos-config.git /tmp/nixos-config
cd /tmp/nixos-config

# 4. Verify disk (WILL ERASE ALL DATA!)
lsblk
# Should be /dev/nvme0n1 - edit disko.nix if different

# 5. Run disko
sudo nix --experimental-features "nix-command flakes" run github:nix-community/disko -- \
  --mode disko \
  /tmp/nixos-config/hosts/samuels-razer/disko.nix

# 6. Install
sudo nixos-install --flake /tmp/nixos-config#samuels-razer --no-root-passwd

# 7. Set password
sudo nixos-enter --root /mnt
passwd samuel
exit

# 8. Reboot
sudo reboot
```

## Post-Install

```bash
# Clone config to permanent location
cd ~/repos
git clone https://github.com/YOUR_USERNAME/nixos-config.git

# Future rebuilds
sudo nixos-rebuild switch --flake ~/repos/nixos-config#samuels-razer
```

## Secure Boot Setup (for Windows Dual-Boot)

1. **Disable Secure Boot** in UEFI temporarily (put in "Setup Mode")

2. **Add secure-boot module** to `configuration.nix`:
   ```nix
   imports = [
     # ... other imports
     ../../modules/system/secure-boot.nix
   ];
   ```

3. **Generate signing keys**:
   ```bash
   sudo sbctl create-keys
   ```

4. **Rebuild** to sign boot files:
   ```bash
   sudo nixos-rebuild switch --flake .#samuels-razer
   ```

5. **Verify** all files are signed:
   ```bash
   sudo sbctl verify
   # All entries should show ✓ Signed
   ```

6. **Enroll keys** (include Microsoft keys for Windows):
   ```bash
   sudo sbctl enroll-keys --microsoft
   ```

7. **Enable Secure Boot** in UEFI/BIOS

8. **Verify** after reboot:
   ```bash
   bootctl status
   # Should show "Secure Boot: enabled"
   ```

## Backup Before Reinstall

If migrating from ext4 to BTRFS, backup first:

```bash
# On current system
rsync -aAXv --exclude={"/dev/*","/proc/*","/sys/*","/tmp/*","/run/*","/mnt/*","/media/*","/lost+found","/nix/*"} / /path/to/backup/

# Important dirs
cp -r ~/.ssh /path/to/backup/
cp -r ~/.gnupg /path/to/backup/
cp -r ~/repos /path/to/backup/
cp -r ~/Nextcloud /path/to/backup/
```
