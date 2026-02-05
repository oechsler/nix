{ config, pkgs, lib, ... }:

let
  cfg = config.features.kernel;
  kernelMap = {
    "cachyos" = pkgs.cachyosKernels.linuxPackages-cachyos-latest;
    "cachyos-lts" = pkgs.cachyosKernels.linuxPackages-cachyos-lts;
    "cachyos-server" = pkgs.cachyosKernels.linuxPackages-cachyos-server;
    "default" = pkgs.linuxPackages;
  };
in
{
  options.features.kernel = lib.mkOption {
    type = lib.types.enum [ "cachyos" "cachyos-lts" "cachyos-server" "default" ];
    default = "cachyos";
    description = "Kernel variant (cachyos, cachyos-lts, cachyos-server, or default NixOS kernel)";
  };

  config = lib.mkMerge [
    {
      boot.kernelPackages = kernelMap.${cfg};

      boot.loader = {
        systemd-boot = {
          enable = true;
          editor = false;
          configurationLimit = 10;
        };
        efi.canTouchEfiVariables = true;
        timeout = 0;
      };
    }

    (lib.mkIf config.features.desktop.enable {
      boot.plymouth.enable = true;
      catppuccin.plymouth.enable = false;

      # Silent boot
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
    })
  ];
}
