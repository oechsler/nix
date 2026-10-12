# System-wide modules, kept in alphabetical order. Feature-specific modules own
# their options and guard their configuration locally.

{ lib, ... }:

{
  nixpkgs.overlays = [
    (_final: prev: {
      python3Packages = prev.python3Packages.overrideScope (
        _pythonFinal: pythonPrev: {
          # Temporary workaround: VTK 9.5.2 falls through to an unavailable
          # external PEGTL despite bundling its compatible copy. Disable
          # external dependencies so VTK builds that bundled copy instead.
          # Remove this override once the upstream packaging issue is fixed.
          vtk = pythonPrev.vtk.overrideAttrs (old: {
            cmakeFlags = (old.cmakeFlags or [ ]) ++ [ (lib.cmakeBool "VTK_USE_EXTERNAL" false) ];
          });
        }
      );
    })
  ];

  imports = [
    ../lib/log.nix
    ./audio.nix
    ./auth.nix
    ./backgrounds.nix
    ./bluetooth.nix
    ./boot.nix
    ./compat.nix
    ./development.nix
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
    ./llm.nix
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
