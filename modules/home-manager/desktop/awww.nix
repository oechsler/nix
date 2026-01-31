{ config, pkgs, inputs, lib, ... }:

let
  awwwPkg = inputs.awww.packages.${pkgs.stdenv.hostPlatform.system}.default;

  wallpaper = ../../../backgrounds/Cloudsnight.jpg;

  startScript = pkgs.writeShellScript "awww-start" ''
    ${awwwPkg}/bin/awww-daemon &
    sleep 2
    ${awwwPkg}/bin/awww img ${wallpaper} --transition-type fade --transition-duration 1
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
  };
}
