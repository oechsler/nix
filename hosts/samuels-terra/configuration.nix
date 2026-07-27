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

{
  config,
  lib,
  pkgs,
  ...
}:

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
      name = "DP-3";
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
    kernel = "cachyos-v4"; # Ryzen 9 9950X3D2 (Zen 5) — x86_64-v4 optimized build
    hardware = {
      formFactor = "desktop";
      cpu = "amd"; # Ryzen 9 9950X3D2 (Zen 5)
      gpu = "amd"; # RX 9070 XT (RDNA4)
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
    # MT7927 (Filogic 380) WiFi/BT non-functional until kernel 7.2+ — disable for now
    wifi.enable = false;
    bluetooth.enable = false;
    wifi.networks = [
      {
        name = "home";
        ssid = "Oechsler!Box";
      }
    ];
    development.opencode.classifier = "local";
  };

  # ASUS ROG STRIX X870-I GAMING WIFI has a phantom USB port 3-7 on the
  # AMD 800 Series Chipset xHCI controller (PCI 0000:71:00.0). The firmware
  # reports the port as "not used" but the controller keeps trying to enumerate
  # it, causing hub_event to hang during suspend with wq_busy=1 (-16 EBUSY).
  #
  # Disable at boot and re-disable after each resume (xHC reset clears port state).
  systemd.services.disable-usb3-port7 = {
    description = "Disable phantom USB port 3-7";
    wantedBy = [ "multi-user.target" ];
    after = [ "sysinit.target" ];
    unitConfig.ConditionPathExists = "/sys/bus/usb/devices/usb3/3-0:1.0/usb3-port7/disable";
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      echo 1 > /sys/bus/usb/devices/usb3/3-0:1.0/usb3-port7/disable
    '';
  };

  # Re-disable after resume (sleep-actions ExecStop runs post-resume).
  systemd.services.sleep-actions.serviceConfig.ExecStop = lib.mkAfter [
    "${pkgs.bash}/bin/bash -c 'port=/sys/bus/usb/devices/usb3/3-0:1.0/usb3-port7/disable; [ -e \"$port\" ] && echo 1 > \"$port\"'"
  ];

  system.stateVersion = "26.11";
}
