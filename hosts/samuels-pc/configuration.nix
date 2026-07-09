# samuels-pc Host Configuration
#
# Desktop workstation configuration.
#
# Hardware:
# - Ryzen 9 5950X (Zen 3) + RX 7900 XTX (RDNA3)
# - Dual 1440p 165Hz monitors (DP-1, DP-2)
# - Dedicated /mnt/games partition (1TB for Steam library)
#
# Features:
# - Secure Boot enabled
# - Dual-boot setup (Windows on separate disk)
# - Hyprland desktop (can switch to KDE in flake)
#
# Theme:
# - Catppuccin Lavender accent
# - Nix-Logo wallpaper
#
# Monitor layout:
# - DP-1 (right): Workspaces 1-4
# - DP-2 (left): Workspaces 5-8

{ ... }:

{
  imports = [
    ./disko.nix
    ./hardware-configuration.nix
    ./luks.nix

    ../../modules
  ];

  networking.hostName = "samuels-pc";

  #===========================
  # Host-specific Overrides
  #===========================
  theme.catppuccin.accent = "lavender";

  # Ensure samuel owns /mnt/games (mounted by disko)
  systemd.tmpfiles.rules = [
    "Z /mnt/games 0755 samuel users -"
  ];

  displays.monitors = [
    {
      name = "DP-1";
      width = 2560;
      height = 1440;
      refreshRate = 165;
      x = 2560;
      y = 0;
      vrr = true;
      workspaces = [
        1
        2
        3
        4
      ];
    }
    {
      name = "DP-2";
      width = 2560;
      height = 1440;
      refreshRate = 165;
      x = 0;
      y = 0;
      vrr = true;
      workspaces = [
        5
        6
        7
        8
      ];
    }
  ];

  features = {
    kernel = "cachyos-v3"; # Ryzen 9 5950X (Zen 3) — x86_64-v3 optimized build
    hardware.cpu = "amd"; # Ryzen 9 5950X (Zen 3)
    hardware.gpu = "amd"; # RX 7900 XTX (RDNA3)
    secureBoot.enable = true;
    encryption.unlockMethod = "yubikey";
    desktop.login = "greeter";
    desktop.fileManager = "terminal";
    smb.shares = [
      "personal-drive"
      "pika"
    ];
    wifi.networks = [ "home" ];
  };

  system.stateVersion = "25.11";
}
