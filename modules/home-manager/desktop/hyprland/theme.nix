# Hyprland Theme Configuration
#
# This module configures Hyprland-specific theming:
# - Qt theme with Kvantum (Catppuccin)
# - Hide window decoration buttons (no minimize/maximize in tiling WM)
# - Symbolic icons for GTK
#
# Common theming (GTK, cursor, icons):
# - See common/theme.nix

{
  pkgs,
  lib,
  fonts,
  theme,
  ...
}:

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

    # WORKAROUND: catppuccin-nix injects a `colors { _var { _type=lua-inline } }` block
    # that Hyprland removed in 0.47+. Colors are defined manually below via palette.json.
    # Remove once catppuccin/nix#hyprland is updated for current Hyprland.
    catppuccin.hyprland.enable = false;
    catppuccin.kvantum.enable = true;

    # gnome platform theme reads color-scheme from portal (dark mode detection)
    # while QT_STYLE_OVERRIDE=kvantum preserves the Kvantum look
    # mkForce overrides the value set by qt.platformTheme.name = "qtct"
    home.sessionVariables.QT_QPA_PLATFORMTHEME = lib.mkForce "gnome";

    # Flatpak Qt apps can't follow symlinks to /nix/store.
    # The catppuccin Kvantum module creates symlinks via xdg.configFile.
    # Replace both the theme directory AND kvantum.kvconfig with real files.
    home.activation.copyKvantumForFlatpak = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
      KVANTUM_THEME="catppuccin-${theme.catppuccin.flavor}-${theme.catppuccin.accent}"
      KVANTUM_DIR="$HOME/.config/Kvantum/$KVANTUM_THEME"
      KVANTUM_CONF="$HOME/.config/Kvantum/kvantum.kvconfig"

      # Replace theme dir symlink with real files
      if [ -L "$KVANTUM_DIR" ]; then
        SRC=$(readlink -f "$KVANTUM_DIR")
        if [ -d "$SRC" ]; then
          rm -f "$KVANTUM_DIR"
          cp -rL "$SRC" "$KVANTUM_DIR"
        fi
      fi

      # Replace kvantum.kvconfig symlink with real file
      if [ -L "$KVANTUM_CONF" ]; then
        CONTENT=$(cat "$KVANTUM_CONF" 2>/dev/null)
        if [ -n "$CONTENT" ]; then
          rm -f "$KVANTUM_CONF"
          printf '%s\n' "$CONTENT" > "$KVANTUM_CONF"
        fi
      fi
    '';

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
