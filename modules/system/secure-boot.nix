# Secure Boot with lanzaboote
#
# Setup instructions:
# 1. First boot WITHOUT secure boot enabled (in UEFI setup mode)
# 2. Generate keys: sudo sbctl create-keys
# 3. Rebuild: sudo nixos-rebuild switch --flake .#hostname
# 4. Verify: sudo sbctl verify (all files should be signed)
# 5. Enroll keys: sudo sbctl enroll-keys --microsoft
#    (--microsoft includes MS keys for Windows dual-boot)
# 6. Enable Secure Boot in UEFI/BIOS
# 7. Reboot and verify: bootctl status
{ config, lib, pkgs, inputs, ... }:

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
