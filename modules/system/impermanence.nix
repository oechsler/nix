# Impermanence Configuration
#
# Feature toggle: features.impermanence.enable (default: true)
# Extra paths:    features.impermanence.extraPaths = [ "/var/lib/custom" ];
#
# This module configures:
# 1. Impermanent root filesystem (wiped on every boot)
# 2. Persistent storage in /persist (btrfs subvolume)
# 3. Root subvolume rollback at boot (requires encryption)
#
# Why impermanence:
# - Security: Malware and rootkits don't survive reboot
# - Privacy: Temporary files and caches are wiped automatically
# - Reproducibility: System state is defined by NixOS config
# - Debugging: Easy to test changes without persistent side effects
#
# How it works:
# 1. Root filesystem (@) is wiped on every boot (btrfs subvolume delete + recreate)
# 2. Important state is stored in /persist (separate btrfs subvolume)
# 3. Impermanence module binds /persist/* to expected locations (/var/lib/*, etc.)
# 4. User home directories should also use impermanence (home-manager)
#
# Filesystem layout:
#   /         → @ subvolume (ephemeral, wiped on boot)
#   /persist  → @persist subvolume (permanent)
#   /nix      → @nix subvolume (permanent, Nix store)
#
# What persists:
# - NetworkManager WiFi passwords
# - Bluetooth pairings
# - Docker containers/images
# - Waydroid Android images (if enabled)
# - Flatpak apps
# - SSH host keys
# - SOPS secrets
# - Tailscale identity
# - System state (nixos generations, etc.)

{ config, lib, ... }:

let
  # Extract root device from filesystem configuration
  # Works with both LUKS (/dev/mapper/cryptroot) and direct devices
  rootDevice = config.fileSystems."/".device;

  # Convert device path to systemd device unit name
  # Example: /dev/mapper/cryptroot → dev-mapper-cryptroot.device
  systemdDevice = lib.replaceStrings ["/"] ["-"] (lib.removePrefix "/" rootDevice) + ".device";
in
{
  #===========================
  # Configuration
  #===========================

  config = lib.mkIf config.features.impermanence.enable {

    #---------------------------
    # 1. Persistent Directories
    #---------------------------
    # Bind /persist/* to their expected locations
    # Example: /persist/var/lib/bluetooth → /var/lib/bluetooth
    #
    # Directories are added conditionally based on enabled features
    environment.persistence."/persist" = {
      hideMounts = true;  # Don't show bind mounts in df/mount output

      directories = [
        # Network (conditional)
        "/var/lib/NetworkManager"   # Network connections (always, needed for ethernet too)

        # System State (always)
        "/var/lib/nixos"              # NixOS state (users, groups, etc.)
        "/var/lib/sops"               # SOPS secrets
        "/var/lib/systemd/rfkill"     # Radio kill switch state
        "/var/lib/systemd/timers"     # Systemd timer state
        "/var/lib/systemd/coredump"   # Core dumps
      ]
      ++ lib.optionals config.features.wifi.enable [
        "/var/lib/iwd"                # WiFi credentials
      ]
      ++ lib.optionals config.features.bluetooth.enable [
        "/var/lib/bluetooth"          # Bluetooth pairings
      ]
      ++ lib.optionals config.features.tailscale.enable [
        "/var/lib/tailscale"          # Tailscale VPN identity
      ]
      ++ lib.optionals config.features.virtualisation.enable [
        "/var/lib/docker"             # Docker containers/images
      ]
      ++ lib.optionals config.features.virtualisation.waydroid.enable [
        "/var/lib/waydroid"           # Waydroid Android images
      ]
      ++ lib.optionals config.features.flatpak.enable [
        "/var/lib/flatpak"            # Flatpak apps
      ]
      ++ lib.optionals config.features.desktop.enable [
        "/var/lib/sddm"               # SDDM state
      ]
      ++ lib.optionals config.features.secureBoot.enable [
        "/var/lib/sbctl"              # Secure Boot keys
      ]
      ++ config.features.impermanence.extraPaths;

      files = [
        "/etc/machine-id"  # Unique machine identifier
      ];
    };

    #---------------------------
    # 2. SSH Host Keys
    #---------------------------
    # Store SSH host keys in /persist to maintain server identity across reboots
    # Without this, SSH clients would see "WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED"
    #
    # When impermanence is enabled: /persist/etc/ssh/
    # When impermanence is disabled: /etc/ssh/ (standard NixOS location)
    services.openssh.hostKeys = [
      {
        path = "/persist/etc/ssh/ssh_host_ed25519_key";
        type = "ed25519";
      }
      {
        path = "/persist/etc/ssh/ssh_host_rsa_key";
        type = "rsa";
        bits = 4096;
      }
    ];

    #---------------------------
    # 3. Root Subvolume Rollback
    #---------------------------
    # Why: Wipe root filesystem on every boot for impermanence
    #
    # Problem: Without wiping, state accumulates in root (caches, logs, temp files)
    #
    # Solution: Delete and recreate @ subvolume in initrd before mounting root
    #
    # How it works:
    # 1. Run in initrd after device availability (LUKS unlock if encrypted)
    # 2. Mount btrfs root (/) to access subvolumes
    # 3. Delete all nested subvolumes under @ (if any)
    # 4. Delete @ subvolume (the root filesystem)
    # 5. Create new empty @ subvolume
    # 6. Unmount and continue boot (system mounts fresh @ as root)
    #
    # Result: Every boot starts with clean root filesystem
    # Only /persist and /nix survive (separate subvolumes)
    #
    # Device detection: Uses config.fileSystems."/".device (works with LUKS and direct devices)
    boot.initrd.systemd.services.rollback = {
      description = "Rollback btrfs root to empty snapshot";
      wantedBy = [ "initrd.target" ];
      after = lib.mkIf config.features.encryption.enable [ systemdDevice ];  # Wait for LUKS unlock if encrypted
      before = [ "sysroot.mount" ];  # Must complete before mounting root
      unitConfig.DefaultDependencies = "no";
      serviceConfig.Type = "oneshot";
      script = ''
        mkdir -p /mnt

        # Mount btrfs root to access subvolumes
        # subvol=/ means mount the btrfs root (not @ subvolume)
        mount -t btrfs -o subvol=/ ${rootDevice} /mnt

        # Delete all nested subvolumes under @ (e.g., snapshots)
        # cut -f9: Extract subvolume path from btrfs output
        btrfs subvolume list -o /mnt/@ | cut -f9 -d' ' | while read subvol; do
          btrfs subvolume delete "/mnt/$subvol"
        done

        # Delete @ subvolume (the root filesystem)
        btrfs subvolume delete /mnt/@

        # Create new empty @ subvolume
        btrfs subvolume create /mnt/@

        umount /mnt
      '';
    };

    #---------------------------
    # 4. Boot Configuration
    #---------------------------
    # Enable systemd in initrd (required for rollback service)
    boot.initrd.systemd.enable = true;

    # /persist must be available before impermanence binds directories
    fileSystems."/persist".neededForBoot = true;
  };
}
