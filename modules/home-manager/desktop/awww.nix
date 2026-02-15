{ config, pkgs, inputs, lib, theme, displays, ... }:

let
  awwwPkg = inputs.awww.packages.${pkgs.stdenv.hostPlatform.system}.default;

  wallpaperCommands =
    if displays.monitors == [] then
      "${awwwPkg}/bin/awww img ${theme.wallpaperPath} --transition-type fade --transition-duration 1"
    else
      lib.concatStringsSep "\n" (map (m:
        let wp = if m.wallpaper != null then m.wallpaper else theme.wallpaperPath;
        in "${awwwPkg}/bin/awww img ${wp} --outputs ${m.name} --transition-type fade --transition-duration 1"
      ) displays.monitors);

  startScript = pkgs.writeShellScript "awww-start" ''
    ${awwwPkg}/bin/awww-daemon &
    sleep 2
    ${wallpaperCommands}
  '';

  setWallpaperScript = pkgs.writeShellScript "awww-set" wallpaperCommands;
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
        run ${setWallpaperScript}
      fi
    '';
  };
}
