# System-wide modules, kept in alphabetical order. Feature-specific modules own
# their options and guard their configuration locally.

{ lib, ... }:

{
  nixpkgs.overlays = [
    (
      _final: prev:
      let
        trayscaleLibs = prev.symlinkJoin {
          name = "trayscale-libs";
          paths = [
            prev.cairo
            prev.gdk-pixbuf
            prev.gtk4
            prev.libadwaita
            prev.glib.out
            prev.gobject-introspection
            prev.graphene
            prev.pango.out
          ];
        };
      in
      {
        # Trayscale 0.20 fixed a UI hang while requesting an initial netmap;
        # 0.21 is the current release and uses purego's dynamic GTK loading.
        trayscale = prev.trayscale.overrideAttrs (old: {
          version = "0.21.0";
          src = prev.fetchFromGitHub {
            owner = "DeedleFake";
            repo = "trayscale";
            tag = "v0.21.0";
            hash = "sha256-8Wv+jLkGVpPfvEMVBpliOAJNG6/XVX93q3l9qIChVpg=";
          };
          vendorHash = "sha256-bxiloB4cJHY45nMYczEToCExj3ZlvDKqA7yYAbgGmi4=";
          postInstall = ''
            sh ./dist.sh install-data $out
            glib-compile-schemas $out/share/glib-2.0/schemas
          '';
          preFixup = (old.preFixup or "") + ''
            gappsWrapperArgs+=(--set PUREGOTK_LIB_FOLDER "${trayscaleLibs}/lib")
          '';
        });

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
      }
    )
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
