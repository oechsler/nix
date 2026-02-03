{ config, pkgs, ... }:

let
  wallpaper = ../../backgrounds/Cloudsnight.jpg;

  blurredWallpaper = pkgs.runCommand "blurred-wallpaper.jpg" {
    buildInputs = [ pkgs.imagemagick ];
  } ''
    convert ${wallpaper} -blur 0x30 $out
  '';

  cursorTheme = config.theme.cursor.name;
  cursorSize = builtins.floor (1.6 * config.theme.cursor.size);
in
{
  # Keyboard Layout
  services.xserver.xkb = {
    layout = "de";
    variant = "";
  };

  services.displayManager.sddm = {
    enable = true;
    wayland.enable = true;
    settings = {
      General = {
        GreeterEnvironment = "QT_SCALE_FACTOR=1.6,QT_FONT_DPI=96";
      };
      Theme = {
        CursorTheme = cursorTheme;
        CursorSize = cursorSize;
      };
    };
  };

  # Cursor-Paket systemweit verfügbar machen
  environment.systemPackages = [ config.theme.cursor.package ];

  catppuccin.sddm = {
    enable = true;
    background = blurredWallpaper;
    loginBackground = true;
  };
}
