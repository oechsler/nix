{ config, pkgs, lib, ... }:

let
  monitors = config.displays.monitors;

  blurredWallpaper = pkgs.runCommand "blurred-wallpaper.jpg" {
    buildInputs = [ pkgs.imagemagick ];
  } ''
    convert ${config.theme.wallpaper} -blur 0x30 $out
  '';

  cursorTheme = config.theme.cursor.name;
  cursorSize = config.theme.cursor.size;
  monospaceFont = config.fonts.defaults.monospace;

  primaryScale = if monitors != [] then (builtins.head monitors).scale else config.theme.scale;
  scaledDpi = builtins.floor (96 * primaryScale);
  scaledCursorSize = builtins.floor (cursorSize * primaryScale);

  kdeTransform = rot: {
    "normal" = "Normal";
    "90"     = "Rotated90";
    "180"    = "Rotated180";
    "270"    = "Rotated270";
  }.${rot};

  sddmDisplayConfig = builtins.toJSON [{
    name = "";
    data = lib.imap0 (i: m: {
      connectorName = m.name;
      enabled = true;
      mode = {
        size = { width = m.width; height = m.height; };
        refreshRate = m.refreshRate * 1000;
      };
      position = { x = m.x; y = m.y; };
      scale = m.scale;
      transform = kdeTransform m.rotation;
      priority = i;
    }) monitors;
  }];

  isKde = config.features.desktop.wm == "kde";
in
{
  config = lib.mkIf config.features.desktop.enable {
    services.xserver.xkb = {
      layout = config.locale.keyboard;
      variant = "";
    };

    services.displayManager.sddm = {
      enable = true;
      wayland.enable = true;
      settings = {
        General = {
          GreeterEnvironment =
            if isKde
            then "XCURSOR_THEME=${cursorTheme},XCURSOR_SIZE=${toString cursorSize}"
            else "QT_FONT_DPI=${toString scaledDpi},XCURSOR_THEME=${cursorTheme},XCURSOR_SIZE=${toString scaledCursorSize}";
        };
        Theme = {
          CursorTheme = cursorTheme;
          CursorSize = if isKde then cursorSize else scaledCursorSize;
        };
      };
    };

    # SDDM uses kwin_wayland — place kscreen config so monitors are positioned correctly.
    systemd.tmpfiles.rules = lib.mkIf (monitors != []) [
      "d /var/lib/sddm/.config 0755 sddm sddm -"
      "f+ /var/lib/sddm/.config/kwinoutputconfig.json 0644 sddm sddm - ${sddmDisplayConfig}"
    ];

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
  };
}
