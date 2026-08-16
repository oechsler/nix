# Desktop Theme Configuration (Common)
#
# This module configures core theming shared across all window managers:
# - GTK theme (Catppuccin)
# - Icon and cursor themes
# - Catppuccin flavor/accent
# - Electron Wayland support
#
# WM-specific theming:
# - Hyprland: See hyprland/theme.nix (Qt/Kvantum, hidden window buttons)
# - KDE: See kde/theme.nix (Plasma integration, window decorations)

{
  config,
  pkgs,
  lib,
  fonts,
  theme,
  ...
}:

let
  # Theme colors and packages
  inherit (theme.catppuccin) flavor accent;
  isLight = flavor == "latte";

  # Catppuccin palette loaded once, shared across modules
  palette = (lib.importJSON "${config.catppuccin.sources.palette}/palette.json").${flavor}.colors;
  iconName = theme.icons.name;
  iconPackage = theme.icons.package;
  cursorName = theme.cursor.name;
  cursorPackage = theme.cursor.package;
  cursorSize = theme.cursor.size;

  # GTK theme (used by all WMs)
  catppuccinGtk = pkgs.catppuccin-gtk.override {
    accents = [ accent ];
    variant = flavor;
  };
  themeName = "catppuccin-${flavor}-${accent}-standard";

in
{
  #===========================
  # Options
  #===========================

  options = {
    theme.catppuccinPalette = lib.mkOption {
      type = lib.types.attrs;
      readOnly = true;
      default = palette;
      internal = true;
    };

    theme.catppuccin.restartTrigger = lib.mkOption {
      type = lib.types.path;
      readOnly = true;
      default = pkgs.writeText "catppuccin-theme" ''
        ${flavor}
        ${accent}
      '';
      internal = true;
    };
  };

  #===========================
  # Configuration
  #===========================

  config = {
    #---------------------------
    # Generic Theme
    #---------------------------
    # GTK, cursor, catppuccin, session variables

    xdg = {
      # GTK4 ignores the theme package — it loads CSS from ~/.config/gtk-4.0/ directly.
      # These files are generated theme artifacts. The Flatpak activation below
      # turns them into real files, so Home Manager must reclaim them on updates.
      configFile."gtk-4.0/gtk.css" = {
        source = "${catppuccinGtk}/share/themes/${themeName}/gtk-4.0/gtk.css";
        force = true;
      };
      configFile."gtk-4.0/gtk-dark.css" = {
        source = "${catppuccinGtk}/share/themes/${themeName}/gtk-4.0/gtk-dark.css";
        force = true;
      };
    };

    catppuccin = {
      enable = true;
      # autoEnable must match enable to suppress catppuccin/nix migration warning
      autoEnable = true;
      flavor = lib.mkDefault flavor;
      accent = lib.mkDefault accent;
    };

    home = {
      pointerCursor = {
        enable = true;
        name = cursorName;
        package = cursorPackage;
        size = cursorSize;
        gtk.enable = true;
        x11.enable = true;
      };

      # Make GTK theme available to Flatpak apps
      # Flatpak sandbox can't follow symlinks to the Nix store.
      # Replace theme dir symlink AND gtk-4.0 CSS symlinks with real files.
      activation.copyGtkThemeForFlatpak = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        THEME_DIR="$HOME/.local/share/themes/${themeName}"
        SOURCE_DIR="${catppuccinGtk}/share/themes/${themeName}"
        GTK4_DIR="$HOME/.config/gtk-4.0"

        if [ -d "$SOURCE_DIR" ]; then
          [ -e "$THEME_DIR" ] && chmod -R u+w "$THEME_DIR" 2>/dev/null || true
          rm -rf "$THEME_DIR"
          mkdir -p "$(dirname "$THEME_DIR")"
          cp -rL "$SOURCE_DIR" "$THEME_DIR"
        fi

        # Replace gtk-4.0 CSS symlinks with real files (flatpak can't follow Nix store symlinks)
        for css in gtk.css gtk-dark.css; do
          CSS_FILE="$GTK4_DIR/$css"
          if [ -L "$CSS_FILE" ]; then
            CONTENT=$(cat "$CSS_FILE" 2>/dev/null)
            if [ -n "$CONTENT" ]; then
              rm -f "$CSS_FILE"
              printf '%s\n' "$CONTENT" > "$CSS_FILE"
            fi
          fi
        done
      '';

    };

    gtk = {
      enable = true;
      font = {
        inherit (fonts) size;
        name = fonts.ui;
      };
      theme = {
        name = themeName;
        package = catppuccinGtk;
      };
      iconTheme = {
        name = lib.mkForce iconName;
        package = lib.mkForce iconPackage;
      };
      # WebKitGTK/Tauri apps need this to detect dark mode
      gtk3.extraConfig.gtk-application-prefer-dark-theme = !isLight;
      gtk4 = {
        extraConfig.gtk-application-prefer-dark-theme = !isLight;
        theme = null;
      };
    };

    dconf.settings."org/gnome/desktop/interface".color-scheme =
      if isLight then "prefer-light" else "prefer-dark";
  };
}
