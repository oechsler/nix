{ config, pkgs, inputs, lib, theme, ... }:

let
  awwwPkg = inputs.awww.packages.${pkgs.stdenv.hostPlatform.system}.default;

  startScript = pkgs.writeShellScript "awww-start" ''
    ${awwwPkg}/bin/awww-daemon &
    sleep 2
    ${awwwPkg}/bin/awww img ${theme.wallpaper} --transition-type fade --transition-duration 1
  '';
in
{
  options.awww = {
    start = lib.mkOption {
      type = lib.types.path;
      default = startScript;
      readOnly = true;
      description = "Script to start awww daemon and set wallpaper";
    };
  };

  config = {
    home.packages = [ awwwPkg ];

    home.activation.setWallpaper = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      if ${pkgs.procps}/bin/pgrep -x "awww-daemon" > /dev/null 2>&1; then
        run ${awwwPkg}/bin/awww img ${theme.wallpaper} --transition-type fade --transition-duration 1
      fi
    '';
  };
}
