# System-wide modules, kept in alphabetical order. Feature-specific modules own
# their options and guard their configuration locally.

{ ... }:

{
  imports = [
    ../lib/service-logging.nix
    ./audio.nix
    ./auth.nix
    ./backgrounds.nix
    ./bluetooth.nix
    ./boot.nix
    ./compat.nix
    ./data-subvolumes.nix
    ./desktop
    ./displays.nix
    ./features.nix
    ./fonts.nix
    ./gaming.nix
    ./hardware.nix
    ./home-manager.nix
    ./impermanence.nix
    ./input.nix
    ./ldap.nix
    ./locale.nix
    ./networking/base.nix
    ./networking/tailscale.nix
    ./networking/wifi.nix
    ./nix.nix
    ./packages.nix
    ./power.nix
    ./secure-boot.nix
    ./smb.nix
    ./snapshots.nix
    ./sops.nix
    ./ssh.nix
    ./terminal.nix
    ./theme.nix
    ./tpm.nix
    ./users.nix
    ./virtualisation.nix
  ];
}
