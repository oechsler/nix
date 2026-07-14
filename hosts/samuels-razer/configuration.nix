# samuels-razer Host Configuration
#
# Razer Blade Stealth 13 (2018, RZ09-02393) laptop configuration.
#
# Hardware:
# - Intel Core i7-8550U (Kaby Lake-R) + Intel UHD Graphics 620
# - 16 GB LPDDR3-1866 (soldered)
# - 13.3" QHD+ display (3200x1800 @ 60Hz, 1.6x scaling, eDP-1)
#
# Features:
# - KDE Plasma desktop (better for laptop/battery management)
# - Gaming disabled (not primary gaming machine)
# - Smaller terminal font (10pt for high DPI screen)
#
# Differences from samuels-pc:
# - Single internal display vs dual external
# - KDE instead of Hyprland
# - No gaming support
# - Default idle timeouts (shorter, battery-aware)

{ ... }:

{
  imports = [
    ./disko.nix
    ./hardware-configuration.nix
    ./luks.nix

    ../../modules
  ];

  networking.hostName = "samuels-razer";

  #===========================
  # Host-specific Overrides
  #===========================
  displays.monitors = [
    {
      name = "eDP-1";
      width = 3200;
      height = 1800;
      refreshRate = 60;
      scale = 1.6;
      workspaces = [
        1
        2
        3
        4
      ];
    }
  ];
  displays.defaults = {
    vrr = 0;
    hdr = 0;
  };

  features = {
    kernel = "cachyos-v3"; # Intel Core i7-8550U (Kaby Lake-R) — x86_64-v3 optimized build
    hardware.cpu = "intel"; # Intel Core i7-8550U (Kaby Lake-R)
    hardware.gpu = "intel"; # Intel UHD Graphics 620
    # secureBoot.enable is NOT set — Razer BIOS does not reliably support custom key enrollment.
    # TPM-backed LUKS provides the primary boot-time security on this machine.
    encryption.unlockMethod = "yubikey";
    desktop = {
      wm = "kde";
      login = "greeter";
      fileManager = "terminal";
    };
    gaming.enable = false;
    auth.yubikey.enable = true;
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

  fonts.defaults.terminalSize = 10;

  system.stateVersion = "25.11";
}
