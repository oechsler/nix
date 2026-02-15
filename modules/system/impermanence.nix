{ config, lib, ... }:

{
  config = {
    # Persistent directories
    environment.persistence."/persist" = {
      hideMounts = true;

      directories = [
        "/var/lib/bluetooth"
        "/var/lib/docker"
        "/var/lib/flatpak"
        "/var/lib/NetworkManager"
        "/var/lib/nixos"
        "/var/lib/sddm"
        "/var/lib/sops"
        "/var/lib/tailscale"
        "/var/lib/systemd/rfkill"
        "/var/lib/systemd/timers"
        "/var/lib/systemd/coredump"
      ];

      files = [
        "/etc/machine-id"
      ];
    };

    # SSH host keys need special handling
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

    # Wipe root subvolume on boot
    boot.initrd.systemd.services.rollback = {
      description = "Rollback btrfs root to empty snapshot";
      wantedBy = [ "initrd.target" ];
      # Use partlabel instead of filesystem label - more reliable in initrd
      after = [ "dev-disk-by\\x2dpartlabel-disk\\x2dmain\\x2droot.device" ];
      before = [ "sysroot.mount" ];
      unitConfig.DefaultDependencies = "no";
      serviceConfig.Type = "oneshot";
      script = ''
        mkdir -p /mnt
        mount -t btrfs -o subvol=/ /dev/disk/by-partlabel/disk-main-root /mnt

        # Delete all subvolumes under @
        btrfs subvolume list -o /mnt/@ | cut -f9 -d' ' | while read subvol; do
          btrfs subvolume delete "/mnt/$subvol"
        done

        # Delete @ and recreate it
        btrfs subvolume delete /mnt/@
        btrfs subvolume create /mnt/@

        umount /mnt
      '';
    };

    # Needed for initrd systemd
    boot.initrd.systemd.enable = true;

    # Required for impermanence
    fileSystems."/persist".neededForBoot = true;
    fileSystems."/var".neededForBoot = true;
  };
}
