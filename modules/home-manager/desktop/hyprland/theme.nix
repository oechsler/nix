# Hyprland Theme Configuration
#
# This module configures Hyprland-specific theming:
# - Qt theme with Kvantum (Catppuccin)
# - Hide window decoration buttons (no minimize/maximize in tiling WM)
# - Symbolic icons for GTK
#
# Common theming (GTK, cursor, icons):
# - See common/theme.nix

{ pkgs, lib, fonts, theme, ... }:

let
  iconName = theme.icons.name;
in
{
  #===========================
  # Configuration
  #===========================

  config = {
    # Hide window decoration buttons in GTK apps
    # (Tiling WMs don't need minimize/maximize buttons)
    gtk = {
      gtk3.extraConfig.gtk-decoration-layout = "";
      gtk3.extraCss = "* { -gtk-icon-style: symbolic; }";
      gtk4.extraConfig.gtk-decoration-layout = "";
    };

    dconf.settings."org/gnome/desktop/wm/preferences".button-layout = "";

    # Qt theme with Kvantum
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
      general="${fonts.ui},${toString fonts.size},-1,5,50,0,0,0,0,0"
    '';

    xdg.configFile."qt6ct/qt6ct.conf".text = ''
      [Appearance]
      style=kvantum
      icon_theme=${iconName}
      color_scheme_path=
      custom_palette=false

      [Fonts]
      fixed="${fonts.monospace},${toString fonts.size},-1,5,50,0,0,0,0,0"
      general="${fonts.ui},${toString fonts.size},-1,5,50,0,0,0,0,0"
    '';
  };
}
