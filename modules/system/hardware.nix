# Hardware Configuration
#
# This module configures hardware-related system services:
# - CPU microcode updates (when features.hardware.cpu is set)
# - GPU graphics + VA-API drivers (when features.hardware.gpu is set)
# - CoolerControl - Fan control GUI (monitors and controls system fans)
# - zram swap - Compressed RAM swap (100% of RAM, improves performance)
# - Printing disabled (no CUPS service)
#
# features.hardware.gpu = "amd" | "intel" | null:
# - Enables hardware.graphics and the correct VA-API driver (radeonsi / iHD).
# - Applies to all desktop contexts (browser, video players, not just gaming).
# - gaming.nix adds 32-bit AMD libs on top for Steam Remote Play.
#
# zram swap:
# - Uses 100% of available RAM for compressed swap space
# - Improves performance on systems with limited RAM
# - Compression ratio typically 2-3x

{ config, pkgs, lib, ... }:

{
  # Enable all redistributable firmware blobs — required for WiFi, BT, and other
  # peripherals that need binary firmware (e.g. MediaTek MT7925, Intel AX, etc.)
  hardware.enableAllFirmware = true;

  hardware = {
    # CPU microcode updates — loaded at early boot, patches security vulnerabilities.
    cpu.amd.updateMicrocode = lib.mkIf (config.features.hardware.cpu == "amd") true;
    cpu.intel.updateMicrocode = lib.mkIf (config.features.hardware.cpu == "intel") true;

    # Enable graphics support whenever a GPU is configured.
    # VA-API drivers are set here so hardware video decoding works in all contexts
    # (browser, video players) — not just when gaming is enabled.
    graphics = lib.mkIf (config.features.hardware.gpu != null) {
      enable = true;

      extraPackages =
        if config.features.hardware.gpu == "amd" then
          [ pkgs.libvdpau-va-gl ]
        else if config.features.hardware.gpu == "intel" then
          with pkgs; [
            intel-media-driver # iHD VA-API driver (Broadwell+)
            libvdpau-va-gl
          ]
        else
          [ ];
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
  };

  # CoolerControl: fan control GUI — desktop-only (not needed on servers)
  programs.coolercontrol.enable = lib.mkDefault (!config.features.server);

  # Set CoolerControl password from the same sops secret as the user password.
  # Generates an argon2id hash at boot and writes it to /etc/coolercontrol/.passwd.
  # sops.secrets."user/password" is defined in users.nix (merged automatically).
  systemd.services.coolercontrol-passwd = lib.mkIf (!config.features.server) {
    description = "Set CoolerControl password from sops secret";
    wantedBy = [ "multi-user.target" ];
    before = [ "coolercontrold.service" ];
    after = [ "sops-install-secrets.service" ];
    unitConfig.ConditionPathExists = config.sops.age.keyFile;
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script =
      let
        argon2 = "${pkgs.libargon2}/bin/argon2";
      in
      ''
        SALT=$(head -c 16 /dev/urandom | base64 -w0 | tr -d '+/=')
        HASH=$(echo -n "$(cat ${config.sops.secrets."user/password".path})" \
          | ${argon2} "$SALT" -id -m 14 -t 2 -p 1 -l 32 -e)
        echo -n "$HASH" > /etc/coolercontrol/.passwd
        chmod 0600 /etc/coolercontrol/.passwd
      '';
  };

  systemd.services.coolercontrold = lib.mkIf (!config.features.server) {
    after = [ "coolercontrol-passwd.service" ];
    wants = [ "coolercontrol-passwd.service" ];
  };
}
