# Hardware Configuration
#
# This module configures hardware-related system services:
# - CoolerControl - Fan control GUI (monitors and controls system fans)
# - zram swap - Compressed RAM swap (100% of RAM, improves performance)
# - Printing disabled (no CUPS service)
#
# zram swap:
# - Uses 100% of available RAM for compressed swap space
# - Improves performance on systems with limited RAM
# - Compression ratio typically 2-3x

{ config, pkgs, lib, ... }:

{
  # Load GPU driver early and enable graphics — needed for Wayland regardless of gaming.
  # nixos-generate-config may miss newer PCI IDs (RDNA3+/RDNA4) on older live ISOs.
  boot.initrd.kernelModules = lib.mkIf (config.features.hardware.gpu == "amd") [ "amdgpu" ];
  hardware.graphics.enable = lib.mkIf (config.features.hardware.gpu != null) true;

  programs.coolercontrol.enable = true;
  services.printing.enable = false;
  zramSwap = {
    enable = true;
    memoryPercent = 100;
  };

  # Set CoolerControl password from the same sops secret as the user password.
  # Generates an argon2id hash at boot and writes it to /etc/coolercontrol/.passwd.
  # sops.secrets."user/password" is defined in users.nix (merged automatically).
  systemd.services.coolercontrol-passwd = {
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

  systemd.services.coolercontrold = {
    after = [ "coolercontrol-passwd.service" ];
    wants = [ "coolercontrol-passwd.service" ];
  };
}
