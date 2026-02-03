{ config, pkgs, lib, theme, ... }:

let
  flavor = config.catppuccin.flavor;
  accent = config.catppuccin.accent;
  isLight = flavor == "latte";

  # Icon Theme aus zentraler config
  iconName = theme.icons.name;
  iconPackage = theme.icons.package;

  # Cursor aus zentraler config
  cursorName = theme.cursor.name;
  cursorPackage = theme.cursor.package;
  cursorSize = theme.cursor.size;

  # Catppuccin GTK Theme mit richtiger Flavor und Accent
  catppuccinGtk = pkgs.catppuccin-gtk.override {
    accents = [ accent ];
    variant = flavor;
  };

  # Theme-Name Format: catppuccin-{flavor}-{accent}-standard
  themeName = "catppuccin-${flavor}-${accent}-standard";
in
{
  # Cursor systemweit
  home.pointerCursor = {
    name = cursorName;
    package = cursorPackage;
    size = cursorSize;
    gtk.enable = true;
    x11.enable = true;
  };

  # GTK Config
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
    # Keine Window Buttons im Tiling WM
    gtk3.extraConfig = {
      gtk-decoration-layout = "";
    };
    gtk4.extraConfig = {
      gtk-decoration-layout = "";
    };
  };

  # Portal Dark Mode Preference + keine Window Buttons
  dconf.settings."org/gnome/desktop/interface" = {
    color-scheme = if isLight then "prefer-light" else "prefer-dark";
  };
  dconf.settings."org/gnome/desktop/wm/preferences" = {
    button-layout = "";
  };

  # Qt via qtct + Kvantum
  qt = {
    enable = true;
    platformTheme.name = "qtct";
    style.name = "kvantum";
  };

  # Kvantum durch catppuccin Modul
  catppuccin.kvantum.enable = true;

  # Session Variables für Qt
  home.sessionVariables = {
    QT_QPA_PLATFORMTHEME = "qt5ct";
  };

  # Qt Packages
  home.packages = with pkgs; [
    libsForQt5.qt5ct
    kdePackages.qt6ct
    libsForQt5.qtstyleplugin-kvantum
    kdePackages.qtstyleplugin-kvantum
  ];

  # qt5ct Config
  xdg.configFile."qt5ct/qt5ct.conf".text = ''
    [Appearance]
    style=kvantum
    icon_theme=${iconName}
    color_scheme_path=
    custom_palette=false

    [Fonts]
    fixed="Monospace,10,-1,5,50,0,0,0,0,0"
    general="Sans Serif,10,-1,5,50,0,0,0,0,0"
  '';

  # qt6ct Config
  xdg.configFile."qt6ct/qt6ct.conf".text = ''
    [Appearance]
    style=kvantum
    icon_theme=${iconName}
    color_scheme_path=
    custom_palette=false

    [Fonts]
    fixed="Monospace,10,-1,5,50,0,0,0,0,0"
    general="Sans Serif,10,-1,5,50,0,0,0,0,0"
  '';

}
