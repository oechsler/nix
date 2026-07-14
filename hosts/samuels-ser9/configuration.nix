# samuels-ser9 Host Configuration
#
# Beelink SER9 Mini PC desktop/gaming configuration.
#
# Hardware:
# - AMD Ryzen AI 9 HX 370 (Zen 5/Zen 5c, 12C/24T, up to 5.1GHz)
# - Integrated Radeon 890M graphics
# - 32GB LPDDR5X
# - 1TB PCIe 4.0 NVMe SSD
# - HDMI/DP/USB4 triple-display capable
# - 2.5G LAN, WiFi 6, Bluetooth 5.2
#
# Features:
# - Same desktop/gaming stack as samuels-terra and samuels-pc
# - Hyprland desktop with SDDM greeter
# - Steam Machine session available from SDDM
# - Secure Boot + YubiKey-backed LUKS unlock
#
# Monitor layout:
# - DP-1 (right): Workspaces 1-4
# - DP-2 (left): Workspaces 5-8
# - One connector is expected to be USB-C DisplayPort Alt Mode, the other native DP

{ ... }:

{
  imports = [
    ./disko.nix
    ./hardware-configuration.nix
    ./luks.nix

    ../../modules
  ];

  networking.hostName = "samuels-ser9";

  #===========================
  # Host-specific Overrides
  #===========================
  theme.catppuccin.accent = "lavender";

  displays.monitors = [
    {
      name = "DP-1";
      make = "LG Electronics";
      model = "LG ULTRAGEAR";
      serial = "312NTBKE2229";
      width = 2560;
      height = 1440;
      refreshRate = 165;
      x = 2560;
      y = 0;
      vrr = 2;
      hdr = true;
      workspaces = [
        1
        2
        3
        4
      ];
    }
    {
      name = "DP-2";
      make = "LG Electronics";
      model = "LG ULTRAGEAR";
      serial = "312NTVSE2231";
      width = 2560;
      height = 1440;
      refreshRate = 165;
      x = 0;
      y = 0;
      vrr = 2;
      hdr = true;
      workspaces = [
        5
        6
        7
        8
      ];
    }
  ];

  features = {
    kernel = "cachyos-v4"; # Ryzen AI 9 HX 370 (Zen 5/Zen 5c) — x86_64-v4 optimized build
    hardware.cpu = "amd"; # AMD Ryzen AI 9 HX 370
    hardware.gpu = "amd"; # Integrated Radeon 890M
    secureBoot.enable = true;
    encryption.unlockMethod = "yubikey";
    gaming.steamMachine.enable = true;
    desktop.login = "greeter";
    desktop.fileManager = "terminal";
    smb.shares = [
      {
        name = "personal-drive";
        label = "Personal-drive";
        path = "//unas.srv.oechsler.it/Personal-drive";
      }
      {
        name = "pika";
        label = "Pika";
        path = "//unas.srv.oechsler.it/Pika";
      }
    ];
    wifi.networks = [
      {
        name = "home";
        ssid = "Oechsler!Box";
      }
    ];
  };

  system.stateVersion = "26.11";
}
