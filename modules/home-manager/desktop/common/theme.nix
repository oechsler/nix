# Desktop Theme Configuration (Common)
#
# This module configures core theming shared across all window managers:
# - Pinned dock/taskbar applications
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
  features,
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

  # WM detection
  isKde = features.desktop.wm == "kde";
  usesTerminalFileManager = features.desktop.fileManager == "terminal";
in
{
  #===========================
  # Options
  #===========================

  # NOTE: Kickoff menu favorites (pinnedFavorites) cannot be set declaratively.
  # Plasma 6 manages them via kactivitymanagerd's internal stats database.
  # See: https://github.com/nix-community/plasma-manager/issues/376
  options.desktop.pinnedApps = lib.mkOption {
    type = lib.types.listOf lib.types.str;
    default = [ ];
    description = "Pinned dock/taskbar apps as desktop file names (without .desktop suffix)";
  };

  options.theme.catppuccinPalette = lib.mkOption {
    type = lib.types.attrs;
    readOnly = true;
    default = palette;
    internal = true;
  };

  #===========================
  # Configuration
  #===========================

  config = {
    #---------------------------
    # Default Pinned Apps
    #---------------------------
    # Apps shown in KDE taskbar / Hyprland dock
    desktop.pinnedApps = [
      "firefox"
    ]
    ++ lib.optional usesTerminalFileManager "yazi"
    ++ lib.optional (!usesTerminalFileManager) (
      if isKde then "org.kde.dolphin" else "org.gnome.Nautilus"
    )
    ++ [
      "kitty"
    ]
    ++ lib.optionals features.development.enable [
      "nvim"
    ]
    ++ lib.optionals features.apps.enable [
      "obsidian"
    ]
    ++ lib.optionals features.gaming.enable [
      "steam"
    ]
    ++ lib.optionals features.apps.enable [
      "vesktop"
      "spotify"
    ];

    #---------------------------
    # Generic Theme
    #---------------------------
    # GTK, cursor, catppuccin, session variables

    xdg = {
      # Override vesktop desktop entry to show Discord branding
      # (Vesktop is a Discord client, but we want to call it "Discord")
      desktopEntries.vesktop = lib.mkIf features.apps.enable {
        name = "Discord";
        exec = "vesktop %U";
        icon = "discord";
        categories = [
          "Network"
          "InstantMessaging"
          "Chat"
        ];
        genericName = "Internet Messenger";
        settings.StartupWMClass = "Vesktop";
      };

      # GTK4 ignores the theme package — it loads CSS from ~/.config/gtk-4.0/ directly.
      # KDE rewrites these files, so force Home Manager ownership for Plasma sessions.
      configFile."gtk-4.0/gtk.css" = {
        source = "${catppuccinGtk}/share/themes/${themeName}/gtk-4.0/gtk.css";
        force = isKde;
      };
      configFile."gtk-4.0/gtk-dark.css" = {
        source = "${catppuccinGtk}/share/themes/${themeName}/gtk-4.0/gtk-dark.css";
        force = isKde;
      };
    };

    catppuccin = {
      enable = true;
      # autoEnable must match enable to suppress catppuccin/nix migration warning
      autoEnable = true;
      flavor = lib.mkDefault flavor;
      accent = lib.mkDefault accent;
    };

    home.enableNixpkgsReleaseCheck = false;

    home = {
      # Clean up stale .bak files before home-manager checks for conflicts
      # (copied-from-Nix files are read-only; chmod first)
      activation.cleanupBackups = lib.hm.dag.entryBefore [ "checkLinkTargets" ] ''
        rm -f ~/.gtkrc-2.0.bak
        for f in ~/.local/share/themes/*.bak; do
          [ -e "$f" ] || continue
          chmod -R u+w "$f" 2>/dev/null || true
          rm -rf "$f"
        done
      '';

      pointerCursor = {
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
      # WebKitGTK/Tauri apps (CoolerControl) need this to detect dark mode
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
