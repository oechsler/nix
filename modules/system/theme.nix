# Theme Configuration
#
# This module configures:
# 1. Catppuccin color scheme (flavor + accent)
# 2. Icon and cursor themes
# 3. UI parameters (scale, radius, gaps, borders)
# 4. Wallpaper configuration
# 5. Dark theme for root apps (GTK + Qt)
#
# Configuration options:
#   theme.catppuccin.flavor = "mocha";     # Catppuccin flavor (default: "mocha")
#   theme.catppuccin.accent = "mauve";     # Accent color (default: "mauve")
#   theme.scale = 1.0;                     # DPI/Monitor scale (default: 1.0)
#   theme.wallpaper = "nix-black-4k.png";  # Wallpaper filename/path (default: "nix-black-4k.png")
#
# The module automatically:
# - Adjusts icon/cursor themes based on light/dark flavor
# - Configures GTK dark preference for root apps (gparted, etc.)
# - Configures Qt theming for root apps (Hyprland only; KDE manages Qt itself)

{ pkgs, config, lib, ... }:

{
  #===========================
  # Options
  #===========================

  options.theme = {
    # Catppuccin Color Scheme
    catppuccin = {
      flavor = lib.mkOption {
        type = lib.types.enum [ "latte" "frappe" "macchiato" "mocha" ];
        default = "mocha";
        description = "Catppuccin flavor (latte = light, others = dark)";
      };
      accent = lib.mkOption {
        type = lib.types.enum [
          "blue" "flamingo" "green" "lavender" "maroon" "mauve"
          "peach" "pink" "red" "rosewater" "sapphire" "sky" "teal" "yellow"
        ];
        default = "mauve";
        description = "Catppuccin accent color";
      };
    };

    # Icon Theme
    icons = {
      name = lib.mkOption {
        type = lib.types.str;
        default = if config.theme.catppuccin.flavor == "latte"
                  then "Papirus-Light"
                  else "Papirus-Dark";
        description = "Icon theme name (automatically switches light/dark based on flavor)";
      };
      package = lib.mkOption {
        type = lib.types.package;
        default = pkgs.catppuccin-papirus-folders.override {
          flavor = config.theme.catppuccin.flavor;
          accent = config.theme.catppuccin.accent;
        };
        description = "Icon theme package (Papirus with Catppuccin folder colors)";
      };
    };

    # Cursor Theme
    cursor = {
      name = lib.mkOption {
        type = lib.types.str;
        default = if config.theme.catppuccin.flavor == "latte"
                  then "Breeze_Light"
                  else "breeze_cursors";
        description = "Cursor theme name (automatically switches light/dark based on flavor)";
      };
      package = lib.mkOption {
        type = lib.types.package;
        default = pkgs.kdePackages.breeze;
        description = "Cursor theme package";
      };
      size = lib.mkOption {
        type = lib.types.int;
        default = 24;
        description = "Cursor size in pixels";
      };
    };

    # UI Parameters
    scale = lib.mkOption {
      type = lib.types.float;
      default = 1.0;
      description = "DPI/Monitor scale factor (1.0 = 100%, 1.5 = 150%, etc.)";
    };

    radius = {
      small = lib.mkOption {
        type = lib.types.int;
        default = 6;
        description = "Small border radius for progress bars and small elements";
      };
      default = lib.mkOption {
        type = lib.types.int;
        default = 16;
        description = "Default border radius for windows, panels, and notifications";
      };
    };

    gaps = {
      inner = lib.mkOption {
        type = lib.types.int;
        default = 8;
        description = "Inner gaps between windows";
      };
      outer = lib.mkOption {
        type = lib.types.int;
        default = 16;
        description = "Outer gaps at screen edges";
      };
    };

    border = {
      width = lib.mkOption {
        type = lib.types.int;
        default = 2;
        description = "Window border width in pixels";
      };
    };

    # Wallpaper
    wallpaper = lib.mkOption {
      type = lib.types.either lib.types.path lib.types.str;
      default = "nix-black-4k.png";
      description = "Wallpaper: filename in encrypted archive (if backgrounds.enable) or direct path";
    };

    wallpaperPath = lib.mkOption {
      type = lib.types.str;
      description = "Runtime path to the current wallpaper (set by backgrounds module)";
    };

    blurredWallpaperPath = lib.mkOption {
      type = lib.types.str;
      description = "Runtime path to blurred wallpaper for SDDM login screen (set by backgrounds module)";
    };
  };

  #===========================
  # Configuration
  #===========================

  config = lib.mkMerge [

    #---------------------------
    # 1. Base Catppuccin Theme
    #---------------------------
    {
      catppuccin = {
        enable = true;
        flavor = config.theme.catppuccin.flavor;
        accent = config.theme.catppuccin.accent;
      };
    }

    #---------------------------
    # 2. GTK Dark Theme for Root Apps
    #---------------------------
    # Why: Apps run with pkexec (gparted, partition manager, etc.) run as root
    # and need dark theme configuration to match the user's theme.
    #
    # Problem: Root apps don't inherit user theme settings.
    #
    # Solution: Configure dark theme in multiple places:
    # - /etc/gtk-*.0/ - System-wide fallback settings
    # - dconf system db - System-wide defaults
    # - /root/.config/gtk-*.0/ - Root user's config (most reliable)
    #
    # How it works:
    # - pkexec sets HOME=/root, so root apps read /root/.config/
    # - We write gtk-application-prefer-dark-theme=1 to all relevant locations
    # - This ensures root apps (GTK 2/3/4) use dark theme when flavor != "latte"

    (lib.mkIf (config.theme.catppuccin.flavor != "latte") {
      # System-wide GTK dark preference
      environment.etc."gtk-2.0/gtkrc".text = ''
        gtk-application-prefer-dark-theme=1
      '';
      environment.etc."gtk-3.0/settings.ini".text = ''
        [Settings]
        gtk-application-prefer-dark-theme=1
      '';
      environment.etc."gtk-4.0/settings.ini".text = ''
        [Settings]
        gtk-application-prefer-dark-theme=1
      '';

      # dconf system database for GNOME apps
      programs.dconf = {
        enable = true;
        profiles.user.databases = [{
          settings."org/gnome/desktop/interface" = {
            color-scheme = "prefer-dark";
          };
        }];
      };

      # Write dark theme settings directly into root's home directory
      # This is the most reliable method for pkexec apps
      system.activationScripts.rootGtkDark.text = let
        settingsIni = pkgs.writeText "gtk-dark-settings" ''
          [Settings]
          gtk-application-prefer-dark-theme=1
        '';
      in ''
        mkdir -p /root/.config/gtk-3.0 /root/.config/gtk-4.0
        cp ${settingsIni} /root/.config/gtk-3.0/settings.ini
        cp ${settingsIni} /root/.config/gtk-4.0/settings.ini
      '';
    })

    # Light theme: Remove root GTK dark settings
    (lib.mkIf (config.theme.catppuccin.flavor == "latte") {
      programs.dconf = {
        enable = true;
        profiles.user.databases = [{
          settings."org/gnome/desktop/interface" = {
            color-scheme = "prefer-light";
          };
        }];
      };

      system.activationScripts.rootGtkDark.text = ''
        rm -f /root/.config/gtk-3.0/settings.ini /root/.config/gtk-4.0/settings.ini
      '';
    })

    #---------------------------
    # 3. Qt Theming for Root Apps (Hyprland only)
    #---------------------------
    # Why: Qt apps run with pkexec need Catppuccin theme configuration.
    #
    # Problem: Root Qt apps don't inherit user theme settings.
    #
    # Solution: Configure qt5ct/qt6ct and Kvantum theme in /root/.config/
    #
    # How it works:
    # - Set Qt platform theme to qt5ct/qt6ct
    # - Configure Kvantum as the Qt style
    # - Write Catppuccin Kvantum theme to /root/.config/Kvantum/
    # - Link the Kvantum theme files from the Nix store
    #
    # Note: Only on Hyprland — KDE Plasma manages Qt theming itself via Plasma integration

    (lib.mkIf (config.features.desktop.wm != "kde") {
      # Global Qt configuration for root apps
      qt = {
        enable = true;
        platformTheme = "qt5ct";
        style = "kvantum";
      };

      # Qt theming packages
      environment.systemPackages = with pkgs; [
        libsForQt5.qt5ct                    # Qt5 configuration tool
        kdePackages.qt6ct                   # Qt6 configuration tool
        libsForQt5.qtstyleplugin-kvantum    # Kvantum style for Qt5
        kdePackages.qtstyleplugin-kvantum   # Kvantum style for Qt6
      ];

      # Write Qt/Kvantum configuration to root's home directory
      system.activationScripts.rootQtDark = {
        deps = [ ];
        text = let
          flavor = config.theme.catppuccin.flavor;
          iconName = config.theme.icons.name;
          kvantumTheme = "catppuccin-${flavor}-${config.theme.catppuccin.accent}";

          # Qt5 configuration: Use Kvantum style + icon theme
          qt5ctConf = pkgs.writeText "qt5ct.conf" ''
            [Appearance]
            style=kvantum
            icon_theme=${iconName}
            color_scheme_path=
            custom_palette=false
          '';

          # Qt6 configuration: Use Kvantum style + icon theme
          qt6ctConf = pkgs.writeText "qt6ct.conf" ''
            [Appearance]
            style=kvantum
            icon_theme=${iconName}
            color_scheme_path=
            custom_palette=false
          '';

          # Kvantum configuration: Select Catppuccin theme
          # Example: "catppuccin-mocha-mauve"
          kvantumConf = pkgs.writeText "kvantum.kvconfig" ''
            [General]
            theme=${kvantumTheme}
          '';

          # Catppuccin Kvantum theme package
          catppuccinKvantum = pkgs.catppuccin-kvantum.override {
            accent = config.theme.catppuccin.accent;
            variant = flavor;
          };
        in ''
          mkdir -p /root/.config/qt5ct /root/.config/qt6ct /root/.config/Kvantum

          # Copy configuration files
          cp ${qt5ctConf} /root/.config/qt5ct/qt5ct.conf
          cp ${qt6ctConf} /root/.config/qt6ct/qt6ct.conf
          cp ${kvantumConf} /root/.config/Kvantum/kvantum.kvconfig

          # Link Kvantum theme from Nix store
          # Example: /nix/store/.../share/Kvantum/catppuccin-mocha-mauve
          ln -sfn ${catppuccinKvantum}/share/Kvantum/${kvantumTheme} /root/.config/Kvantum/${kvantumTheme}
        '';
      };
    })
  ];
}
