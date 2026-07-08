# Secure Boot with lanzaboote
#
# Setup instructions:
# 1. Run install.sh — it generates sbctl keys automatically before nixos-install
# 2. Boot into the new system (UEFI in Setup Mode, Secure Boot disabled)
# 3. Enroll keys: sudo sbctl enroll-keys --microsoft
#    (--microsoft includes MS keys for Windows dual-boot)
# 4. Enable Secure Boot in UEFI/BIOS
# 5. Reboot and verify: bootctl status
{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:

let
  cfg = config.features.secureBoot;
in
{
  imports = [
    inputs.lanzaboote.nixosModules.lanzaboote
  ];

  options.features.secureBoot = {
    enable = lib.mkEnableOption "Secure Boot via lanzaboote";
  };

  config = lib.mkIf cfg.enable {
    # Lanzaboote replaces systemd-boot
    boot.loader.systemd-boot.enable = lib.mkForce false;

    boot.lanzaboote = {
      enable = true;
      pkiBundle = "/var/lib/sbctl";
    };

    # sbctl for key management
    environment.systemPackages = [ pkgs.sbctl ];
  };
}
