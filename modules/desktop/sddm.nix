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
  monospaceFont = config.fonts.defaults.monospace;
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

  catppuccin.sddm = {
    enable = true;
    font = monospaceFont;
    fontSize = "12";
    background = blurredWallpaper;
    loginBackground = true;
    userIcon = true;
    clockEnabled = false;
  };

  # Cursor-Paket systemweit verfügbar machen
  environment.systemPackages = [
    config.theme.cursor.package
  ];
}
