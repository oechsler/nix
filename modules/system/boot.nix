{ config, pkgs, ... }:

{
  # CachyOS Kernel - optimiert für Desktop/Gaming (BORE scheduler, etc.)
  boot.kernelPackages = pkgs.cachyosKernels.linuxPackages-cachyos-latest;

  # systemd-boot Konfiguration
  boot.loader = {
    systemd-boot = {
      enable = true;
      editor = false;           # Kernel-Parameter-Editor deaktivieren (Sicherheit)
      configurationLimit = 10;  # Nur letzte 10 Generationen anzeigen
    };
    efi.canTouchEfiVariables = true;
    timeout = 0;                # Kein Menü, direkt booten
  };

  # Plymouth boot splash
  boot.plymouth.enable = true;
  catppuccin.plymouth.enable = false;

  # Sauberer Boot ohne Kernel-Messages
  boot.consoleLogLevel = 0;
  boot.initrd.verbose = false;
  boot.kernelParams = [
    "quiet"
    "splash"
    "boot.shell_on_fail"
    "loglevel=3"
    "rd.systemd.show_status=false"
    "rd.udev.log_level=3"
    "udev.log_priority=3"
  ];
}
