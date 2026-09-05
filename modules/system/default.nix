# System-wide modules, kept in alphabetical order. Feature-specific modules own
# their options and guard their configuration locally.

{ ... }:

{
  imports = [
    ../lib/log.nix
    ./audio.nix
    ./auth.nix
    ./backgrounds.nix
    ./bluetooth.nix
    ./boot.nix
    ./compat.nix
    ./mount.nix
    ./desktop
    ./disko-luks.nix
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
    ./ollama.nix
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
