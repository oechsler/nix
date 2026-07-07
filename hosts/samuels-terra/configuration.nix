# samuels-terra Host Configuration
#
# Desktop workstation configuration.
#
# Hardware:
# - Dual 1440p 165Hz monitors (DP-1, DP-2)
# - Samsung 9100 Pro 2TB NVMe (single disk, no separate games partition)
#
# Features:
# - Secure Boot enabled
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

  networking.hostName = "samuels-terra";

  #===========================
  # Host-specific Overrides
  #===========================
  theme.catppuccin.accent = "lavender";

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
    kernel = "cachyos-v4"; # Ryzen 9 9950X3D (Zen 5) — x86_64-v4 optimized build
    secureBoot.enable = true;
    encryption.unlockMethod = "yubikey";
    desktop.login = "greeter";
    desktop.fileManager = "terminal";
    gaming.gpu = "amd"; # RX 9070 XT (RDNA4) — enables VA-API hardware encoding
    smb.shares = [
      "personal-drive"
      "pika"
    ];
    wifi.networks = [ "home" ];
  };

  system.stateVersion = "25.11";
}
