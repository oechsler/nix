# samuels-terra Host Configuration
#
# Desktop workstation configuration.
#
# Hardware:
# - Ryzen 9 9950X3D2 (Zen 5) + RX 9070 XT (RDNA4)
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
# - DP-2 (right): Workspaces 1-4
# - DP-3 (left): Workspaces 5-8

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
      name = "DP-2";
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
      name = "DP-3";
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
    kernel = "cachyos-v4"; # Ryzen 9 9950X3D2 (Zen 5) — x86_64-v4 optimized build
    hardware.cpu = "amd"; # Ryzen 9 9950X3D2 (Zen 5)
    hardware.gpu = "amd"; # RX 9070 XT (RDNA4)
    secureBoot.enable = true;
    encryption.unlockMethod = "yubikey";
    gaming.steamMachine.enable = true;
    desktop.login = "greeter";
    desktop.fileManager = "terminal";
    smb.shares = [
      { name = "personal-drive"; label = "Personal-drive"; path = "//unas.srv.oechsler.it/Personal-drive"; }
      { name = "pika";           label = "Pika";           path = "//unas.srv.oechsler.it/Pika"; }
    ];
    # MT7927 (Filogic 380) WiFi/BT non-functional until kernel 7.2+ — disable for now
    wifi.enable = false;
    bluetooth.enable = false;
    wifi.networks = [ { name = "home"; ssid = "Oechsler!Box"; } ];
  };

  system.stateVersion = "26.11";
}
