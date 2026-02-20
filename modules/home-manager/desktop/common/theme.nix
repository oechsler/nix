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

{ config, pkgs, lib, fonts, theme, features, ... }:

let
  # Theme colors and packages
  flavor = theme.catppuccin.flavor;
  accent = theme.catppuccin.accent;
  isLight = flavor == "latte";
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
    default = [];
    description = "Pinned dock/taskbar apps as desktop file names (without .desktop suffix)";
  };

  #===========================
  # Configuration
  #===========================

  config = {
    #---------------------------
    # Default Pinned Apps
    #---------------------------
    # Apps shown in KDE taskbar / Hyprland dock
    desktop.pinnedApps =
      [ "firefox"
        (if isKde then "org.kde.dolphin" else "org.gnome.Nautilus")
        "kitty"
      ]
      ++ lib.optionals features.development.enable [
        "code"
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

    # Override vesktop desktop entry to show Discord branding
    # (Vesktop is a Discord client, but we want to call it "Discord")
    xdg.desktopEntries.vesktop = lib.mkIf features.apps.enable {
      name = "Discord";
      exec = "vesktop %U";
      icon = "discord";
      categories = [ "Network" "InstantMessaging" "Chat" ];
      genericName = "Internet Messenger";
      settings.StartupWMClass = "Vesktop";
    };

    # Clean up stale .bak files before home-manager checks for conflicts
    home.activation.cleanupBackups = lib.hm.dag.entryBefore [ "checkLinkTargets" ] ''
      rm -f ~/.gtkrc-2.0.bak
    '';

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
      font = {
        name = fonts.ui;
        size = fonts.size;
      };
      theme = {
        name = themeName;
        package = catppuccinGtk;
      };
      iconTheme = {
        name = lib.mkForce iconName;
        package = lib.mkForce iconPackage;
      };
    };

    # Electron apps (Discord, VS Code, …) natively on Wayland
    home.sessionVariables.NIXOS_OZONE_WL = "1";

    dconf.settings."org/gnome/desktop/interface".color-scheme =
      if isLight then "prefer-light" else "prefer-dark";
  };
}
