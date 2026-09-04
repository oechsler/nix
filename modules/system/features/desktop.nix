# Desktop session and integration feature options.

{ config, lib, ... }:

{
  options.features = {
    desktop = {
      enable = (lib.mkEnableOption "desktop environment (Hyprland, SDDM, LibreWolf)") // {
        default = config.features.hardware.formFactor != "headless";
      };
      wm = lib.mkOption {
        type = lib.types.enum [
          "hyprland"
          "kde"
        ];
        default = "hyprland";
        description = "Window manager / desktop environment";
      };
      login = lib.mkOption {
        type = lib.types.enum [
          "greeter"
          "autologin"
        ];
        default = "greeter";
        description = "How the desktop session is entered after boot.";
      };
      fileManager = lib.mkOption {
        type = lib.types.enum [
          "default"
          "terminal"
        ];
        default = "default";
        description = "Primary file manager for the desktop environment";
      };
      tray.icons = lib.mkOption {
        type = lib.types.attrsOf lib.types.str;
        default = { };
        description = "Custom StatusNotifierItem IDs to Papirus icon name mappings for Waybar.";
      };
      pinnedApps = {
        entries = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default =
            lib.optional config.features.desktop.browser.enable config.features.desktop.browser.type
            ++ lib.optional (config.features.desktop.fileManager == "terminal") "yazi"
            ++ lib.optional (config.features.desktop.fileManager != "terminal") (
              if config.features.desktop.wm == "kde" then "org.kde.dolphin" else "org.gnome.Nautilus"
            )
            ++ [ "kitty" ]
            ++ lib.optionals config.features.dev.enable [ "nvim" ]
            ++ lib.optionals config.features.apps.enable [ "md.Obsidian" ]
            ++ lib.optionals config.features.gaming.enable [ "steam" ]
            ++ lib.optionals config.features.apps.enable [ "vesktop" ]
            ++ lib.optional (
              config.features.apps.enable && config.features.apps.mumble.enable
            ) "info.mumble.Mumble"
            ++ lib.optionals config.features.apps.enable [ "spotify" ];
          description = "Pinned dock/taskbar apps as desktop file names (without .desktop suffix).";
        };
        declarative = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Whether pinned dock/taskbar apps are enforced on every desktop start.";
        };
      };
      kde = {
        tray = {
          shown = lib.mkOption {
            type = lib.types.nullOr (lib.types.listOf lib.types.str);
            default = null;
            description = "KDE system-tray items shown directly in the panel.";
          };
          hidden = lib.mkOption {
            type = lib.types.nullOr (lib.types.listOf lib.types.str);
            default = null;
            description = "KDE system-tray items hidden behind the tray popup.";
          };
        };
        favorites = {
          entries = lib.mkOption {
            type = lib.types.nullOr (lib.types.listOf lib.types.str);
            default = null;
            description = "KDE Kickoff favorites as desktop file names.";
          };
          declarative = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = "Whether KDE Kickoff favorites are enforced on every KDE start instead of initialized once.";
          };
        };
      };
      browser = {
        enable = (lib.mkEnableOption "default web browser") // {
          default = true;
        };
        type = lib.mkOption {
          type = lib.types.enum [
            "librewolf"
            "firefox"
          ];
          default = "librewolf";
          description = "Default web browser";
        };
        newTabPage = lib.mkOption {
          type = lib.types.str;
          default = "https://dash.at.oechsler.it";
          description = "URL used by the managed new-tab page";
        };
        searchEngine = lib.mkOption {
          type = lib.types.str;
          default = "ddg";
          description = "Default browser search engine identifier";
        };
        cookieAllowlist = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          description = "Additional sites allowed to keep first-party cookies and sessions";
        };
      };
    };

    fileManager.bookmarks = lib.mkOption {
      type = lib.types.nullOr (
        lib.types.listOf (
          lib.types.submodule {
            options = {
              name = lib.mkOption {
                type = lib.types.str;
                description = "Display name";
              };
              path = lib.mkOption {
                type = lib.types.str;
                description = "Absolute path";
              };
              icon = lib.mkOption {
                type = lib.types.str;
                default = "folder";
                description = "Icon name";
              };
            };
          }
        )
      );
      default = null;
      description = "File manager sidebar bookmarks (used by Nautilus and Dolphin).";
    };
  };
}
