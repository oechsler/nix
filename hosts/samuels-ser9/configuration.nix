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
# - Same desktop/gaming stack as samuels-terra
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
      hdr = 1;
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
      hdr = 1;
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
    hardware = {
      formFactor = "desktop";
      cpu = "amd"; # AMD Ryzen AI 9 HX 370
      gpu = "amd"; # Integrated Radeon 890M
    };
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

    ops = {
      pvetui = {
        defaultProfile = "server-1";
        profiles = [
          {
            name = "server-1";
            addr = "https://proxmox-1.lan.oechsler.it:8006";
          }
          {
            name = "server-2";
            addr = "https://proxmox-2.lan.oechsler.it:8006";
          }
        ];
      };

      kubernetes = {
        defaultContext = "k3s.oechsler.it";
        clusters = [
          {
            name = "k3s.oechsler.it";
            server = "https://k3s.oechsler.it:6443";
            caData = "LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUJkakNDQVIyZ0F3SUJBZ0lCQURBS0JnZ3Foa2pPUFFRREFqQWpNU0V3SHdZRFZRUUREQmhyTTNNdGMyVnkKZG1WeUxXTmhRREUzT0RJd05qazVNekl3SGhjTk1qWXdOakl4TVRneU5UTXlXaGNOTXpZd05qRTRNVGd5TlRNeQpXakFqTVNFd0h3WURWUVFEREJock0zTXRjMlZ5ZG1WeUxXTmhRREUzT0RJd05qazVNekl3V1RBVEJnY3Foa2pPClBRSUJCZ2dxaGtqT1BRTUJCd05DQUFRZFdSMTlKS1BxM29VYjRJR2tYWWFBN3NlY2JQQkVPNWhjNFF1YzFrVW0KcytVeDlicG9haElCWFkzNTNYUXM3Y2NCcGVUSjA3NHd1VUFLM0ZxdTR4NGFvMEl3UURBT0JnTlZIUThCQWY4RQpCQU1DQXFRd0R3WURWUjBUQVFIL0JBVXdBd0VCL3pBZEJnTlZIUTRFRmdRVVk1N3p3TERONC9wZVhaYlZlejU5CmtERWVvZW93Q2dZSUtvWkl6ajBFQXdJRFJ3QXdSQUlnUFJnUFhiTUtSZm5SMzNOV2F1R1FGbUV6SnA3djlRdDEKYkhUN0lGU3V1cmtDSUVjRENxSGV5S2NsWENYaGxXR0lxQ2hIQUpOZWt6c2hOVnZQZldhaFBUM04KLS0tLS1FTkQgQ0VSVElGSUNBVEUtLS0tLQo=";
            namespace = "default";
            oidc = {
              issuerUrl = "https://id.at.oechsler.it";
              clientId = "f18b9f65-0a3c-4fea-ace3-73954937bcd1";
            };
          }
        ];
      };
    };
  };

  system.stateVersion = "26.11";
}
