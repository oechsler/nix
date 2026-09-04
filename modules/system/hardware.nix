# Hardware Configuration
#
# This module configures hardware-related system services:
# - CPU microcode updates (when features.hardware.cpu is set)
# - GPU graphics + VA-API drivers (when features.hardware.gpu is set)
# - zram swap - Compressed RAM swap (% of RAM, capped at 32 GiB)
# - Printing disabled (no CUPS service)
#
# features.hardware.gpu = "amd" | "intel" | null:
# - Enables hardware.graphics and the correct VA-API driver (radeonsi / iHD).
# - Applies to all desktop contexts (browser, video players, not just gaming).
# - gaming.nix adds 32-bit AMD libs on top for Steam Remote Play.
#
# zram swap:
# - Uses 100% of available RAM for compressed swap space
# - Hard-capped at 32 GiB so large-RAM machines don't over-allocate swap
# - On ≤ 32 GiB machines → swap = RAM; on ≥ 32 GiB → swap = 32 GiB.
# - Compression ratio typically 2-3x

{
  config,
  pkgs,
  lib,
  ...
}:

{
  # Enable all redistributable firmware blobs — required for WiFi, BT, and other
  # peripherals that need binary firmware (e.g. MediaTek MT7925, Intel AX, etc.)
  hardware.enableAllFirmware = true;

  hardware = {
    # CPU microcode updates — loaded at early boot, patches security vulnerabilities.
    cpu.amd.updateMicrocode = lib.mkIf (config.features.hardware.cpu == "amd") true;
    cpu.intel.updateMicrocode = lib.mkIf (config.features.hardware.cpu == "intel") true;

    i2c.enable = true;

    # Enable graphics support whenever a GPU is configured.
    # VA-API drivers are set here so hardware video decoding works in all contexts
    # (browser, video players) — not just when gaming is enabled.
    graphics = lib.mkIf (config.features.hardware.gpu != null) {
      enable = true;

      extraPackages = [
        pkgs.ocl-icd
      ]
      ++ (
        if config.features.hardware.gpu == "amd" then
          [
            pkgs.libvdpau-va-gl
            pkgs.rocmPackages.clr.icd
          ]
        else if config.features.hardware.gpu == "intel" then
          with pkgs;
          [
            intel-media-driver # iHD VA-API driver (Broadwell+)
            libvdpau-va-gl
            intel-compute-runtime # OpenCL runtime
          ]
        else
          [ ]
      );
    };
  };

  environment.sessionVariables = lib.mkIf (config.features.hardware.gpu != null) (
    if config.features.hardware.gpu == "amd" then
      { LIBVA_DRIVER_NAME = "radeonsi"; }
    else if config.features.hardware.gpu == "intel" then
      { LIBVA_DRIVER_NAME = "iHD"; }
    else
      { }
  );

  services.printing.enable = false;
  zramSwap = {
    enable = true;
    memoryPercent = 100;
    memoryMax = 32 * 1024 * 1024 * 1024; # 32 GiB hard cap
  };

  # AMD CPU: ensure active pstate driver for modern EPP-based scaling.
  # Required for power-profiles-daemon to control performance profiles on AMD.
  boot.kernelParams =
    lib.mkIf (config.features.hardware.cpu == "amd" || config.features.hardware.unifiedMemory.enable)
      (
        lib.optional (config.features.hardware.cpu == "amd") "amd_pstate=active"
        ++ lib.optional (
          config.features.hardware.unifiedMemory.enable && config.features.hardware.unifiedMemory.size != null
        ) "amdgpu.gttsize=${toString config.features.hardware.unifiedMemory.size}"
      );

  assertions = [
    {
      assertion =
        !config.features.hardware.unifiedMemory.enable
        || (config.features.hardware.cpu == "amd" && config.features.hardware.gpu == "amd");
      message = "features.hardware.unifiedMemory.enable requires both CPU and GPU to be AMD.";
    }
    {
      assertion =
        !config.features.hardware.unifiedMemory.enable
        || config.features.hardware.unifiedMemory.size != null;
      message = "features.hardware.unifiedMemory.enable requires an explicit unifiedMemory.size.";
    }
    {
      assertion = config.features.hardware.formFactor != "headless" || !config.features.desktop.enable;
      message = "headless systems cannot enable features.desktop.enable.";
    }
    {
      assertion = config.features.hardware.formFactor != "headless" || !config.features.apps.enable;
      message = "headless systems cannot enable features.apps.enable.";
    }
  ];

}
