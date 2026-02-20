# System Configuration Modules
#
# This module imports all system-level configuration modules.
#
# Categories:
# - Core: nix, boot, networking, locale, users
# - Security: sops, secure-boot, compat
# - Hardware: audio, bluetooth, fonts, theme, displays, input
# - Storage: impermanence, snapshots, smb, backgrounds
# - Services: power, virtualisation, gaming, ssh
# - Integration: packages, features, home-manager

{ ... }:

{
  imports = [
    ./nix.nix
    ./sops.nix
    ./boot.nix
    ./secure-boot.nix
    ./compat.nix
    ./networking.nix
    ./locale.nix
    ./users.nix
    ./audio.nix
    ./bluetooth.nix
    ./fonts.nix
    ./theme.nix
    ./backgrounds.nix
    ./impermanence.nix
    ./hardware.nix
    ./virtualisation.nix
    ./power.nix
    ./smb.nix
    ./gaming.nix
    ./packages.nix
    ./ssh.nix
    ./snapshots.nix
    ./features.nix
    ./displays.nix
    ./input.nix
    ./home-manager.nix
  ];
}
