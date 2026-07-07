# Boot Configuration
#
# This module configures the boot process and kernel:
# - Kernel selection (CachyOS optimized or default NixOS kernel)
# - systemd-boot bootloader with EFI support
# - Plymouth boot splash (when desktop is enabled)
# - Silent boot (minimal boot messages)
#
# Configuration:
#   features.kernel = "cachyos";        # Options: cachyos, cachyos-v3, cachyos-v4, cachyos-lts, cachyos-server, default
#
# Boot behavior:
# - Configuration limit: Keep last 10 boot entries
# - Boot timeout: 0 seconds (instant boot to default)
# - Desktop mode: Silent boot with Plymouth splash screen
# - No bootloader editor access (security)

{
  config,
  pkgs,
  lib,
  ...
}:

let
  cfg = config.features.kernel;
  kernelMap = {
    "cachyos" = pkgs.cachyosKernels.linuxPackages-cachyos-latest;
    "cachyos-v3" = pkgs.cachyosKernels.linuxPackages-cachyos-latest-x86_64-v3;
    "cachyos-v4" = pkgs.cachyosKernels.linuxPackages-cachyos-latest-x86_64-v4;
    "cachyos-lts" = pkgs.cachyosKernels.linuxPackages-cachyos-lts;
    "cachyos-server" = pkgs.cachyosKernels.linuxPackages-cachyos-server;
    "default" = pkgs.linuxPackages;
  };
in
{
  options.features.kernel = lib.mkOption {
    type = lib.types.enum [
      "cachyos"
      "cachyos-v3"
      "cachyos-v4"
      "cachyos-lts"
      "cachyos-server"
      "default"
    ];
    default = "cachyos";
    description = "Kernel variant (cachyos, cachyos-v3, cachyos-v4, cachyos-lts, cachyos-server, or default NixOS kernel)";
  };

  config = lib.mkMerge [
    {
      boot = {
        kernelPackages = kernelMap.${cfg};

        loader = {
          systemd-boot = {
            enable = true;
            editor = false;
            configurationLimit = 10;
          };
          efi.canTouchEfiVariables = true;
          timeout = 0;
        };

        # Bump inotify limits for dev tooling (LSP servers, file watchers, etc.).
        # Default 8192 is far too low for modern projects.
        # NOTE: nvim-tree ENOSPC was a btrfs/libuv bug, not an inotify limit issue.
        kernel.sysctl = {
          "fs.inotify.max_user_watches" = 524288;
          "fs.inotify.max_user_instances" = 512;
        };
      };

      # Cgroup-aware inotify limit for user sessions (systemd path units, etc.)
      systemd.settings.Manager.DefaultMemoryInotifyMax = "524288";
    }

    (lib.mkIf config.features.desktop.enable {
      boot = {
        plymouth.enable = true;

        # Silent boot
        consoleLogLevel = 0;
        initrd.verbose = false;
        kernelParams = [
          "quiet"
          "splash"
          "boot.shell_on_fail"
          "loglevel=3"
          "rd.systemd.show_status=false"
          "rd.udev.log_level=3"
          "udev.log_priority=3"
        ];
      };
      catppuccin.plymouth.enable = false;
    })
  ];
}
