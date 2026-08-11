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
# Differences from samuels-terra:
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
    # --- Hardware & Kernel ---
    kernel = "cachyos-v3"; # Intel Core i7-8550U (Kaby Lake-R) — x86_64-v3 optimized build
    hardware = {
      formFactor = "laptop";
      cpu = "intel"; # Intel Core i7-8550U (Kaby Lake-R)
      gpu = "intel"; # Intel UHD Graphics 620
    };

    # --- Boot & Security ---
    # secureBoot.enable is NOT set — Razer BIOS does not reliably support custom key enrollment.
    # TPM-backed LUKS provides the primary boot-time security on this machine.
    encryption.unlockMethod = "yubikey";
    auth.yubikey.enable = true;

    # --- Networking ---
    wifi.networks = [
      {
        name = "home";
        ssid = "Oechsler!Box";
      }
    ];

    # --- System Services ---
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

    # --- Desktop & UI ---
    desktop = {
      wm = "kde";
      login = "greeter";
      fileManager = "terminal";
    };
    gaming.enable = false;

    # --- Operations Tools ---
    ops = {
      pvetui = {
        defaultProfile = "all-servers";
        groups = {
          "all-servers" = {
            mode = "aggregate";
          };
        };
        profiles = [
          {
            name = "server-1";
            addr = "https://proxmox-1.lan.oechsler.it";
            sshAddr = "server-1.srv.oechsler.it";
            groups = [ "all-servers" ];
          }
          {
            name = "server-2";
            addr = "https://proxmox-2.lan.oechsler.it";
            sshAddr = "server-2.srv.oechsler.it";
            groups = [ "all-servers" ];
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

  fonts.defaults.terminalSize = 10;

  system.stateVersion = "25.11";
}
