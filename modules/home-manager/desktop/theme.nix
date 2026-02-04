{ config, pkgs, lib, fonts, theme, ... }:

let
  flavor = theme.catppuccin.flavor;
  accent = theme.catppuccin.accent;
  isLight = flavor == "latte";
  iconName = theme.icons.name;
  iconPackage = theme.icons.package;
  cursorName = theme.cursor.name;
  cursorPackage = theme.cursor.package;
  cursorSize = theme.cursor.size;

  catppuccinGtk = pkgs.catppuccin-gtk.override {
    accents = [ accent ];
    variant = flavor;
  };
  themeName = "catppuccin-${flavor}-${accent}-standard";
in
{
  catppuccin = {
    enable = true;
    flavor = lib.mkDefault flavor;
    accent = lib.mkDefault accent;
  };

  home.pointerCursor = {
    name = cursorName;
    package = cursorPackage;
    size = cursorSize;
    gtk.enable = true;
    x11.enable = true;
  };

  gtk = {
    enable = true;
    theme = {
      name = themeName;
      package = catppuccinGtk;
    };
    iconTheme = {
      name = lib.mkForce iconName;
      package = lib.mkForce iconPackage;
    };
    # No window buttons in tiling WM
    gtk3.extraConfig.gtk-decoration-layout = "";
    gtk4.extraConfig.gtk-decoration-layout = "";
  };

  dconf.settings."org/gnome/desktop/interface".color-scheme =
    if isLight then "prefer-light" else "prefer-dark";
  dconf.settings."org/gnome/desktop/wm/preferences".button-layout = "";

  qt = {
    enable = true;
    platformTheme.name = "qtct";
    style.name = "kvantum";
  };

  catppuccin.kvantum.enable = true;

  home.sessionVariables.QT_QPA_PLATFORMTHEME = "qt5ct";

  home.packages = with pkgs; [
    libsForQt5.qt5ct
    kdePackages.qt6ct
    libsForQt5.qtstyleplugin-kvantum
    kdePackages.qtstyleplugin-kvantum
  ];

  xdg.configFile."qt5ct/qt5ct.conf".text = ''
    [Appearance]
    style=kvantum
    icon_theme=${iconName}
    color_scheme_path=
    custom_palette=false

    [Fonts]
    fixed="${fonts.monospace},${toString fonts.size},-1,5,50,0,0,0,0,0"
    general="${fonts.sansSerif},${toString fonts.size},-1,5,50,0,0,0,0,0"
  '';

  xdg.configFile."qt6ct/qt6ct.conf".text = ''
    [Appearance]
    style=kvantum
    icon_theme=${iconName}
    color_scheme_path=
    custom_palette=false

    [Fonts]
    fixed="${fonts.monospace},${toString fonts.size},-1,5,50,0,0,0,0,0"
    general="${fonts.sansSerif},${toString fonts.size},-1,5,50,0,0,0,0,0"
  '';
}
