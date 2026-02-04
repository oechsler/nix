{ config, pkgs, ... }:

let
  blurredWallpaper = pkgs.runCommand "blurred-wallpaper.jpg" {
    buildInputs = [ pkgs.imagemagick ];
  } ''
    convert ${config.theme.wallpaper} -blur 0x30 $out
  '';

  scale = config.theme.scale;
  cursorTheme = config.theme.cursor.name;
  cursorSize = builtins.floor (scale * config.theme.cursor.size);
  monospaceFont = config.fonts.defaults.monospace;
in
{
  services.xserver.xkb = {
    layout = config.locale.keyboard;
    variant = "";
  };

  services.displayManager.sddm = {
    enable = true;
    wayland.enable = true;
    settings = {
      General = {
        GreeterEnvironment = "QT_SCALE_FACTOR=${toString scale},QT_FONT_DPI=96";
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

  environment.systemPackages = [
    config.theme.cursor.package
  ];
}
