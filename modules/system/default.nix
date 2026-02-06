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
    ./hardware.nix
    ./virtualisation.nix
    ./power.nix
    ./smb.nix
    ./gaming.nix
    ./packages.nix
    ./ssh.nix
    ./features.nix
    ./displays.nix
    ./input.nix
    ./home-manager.nix
  ];
}
