{ pkgs, config, lib, ... }:

{
  options.theme = {
    catppuccin = {
      flavor = lib.mkOption {
        type = lib.types.enum [ "latte" "frappe" "macchiato" "mocha" ];
        default = "mocha";
        description = "Catppuccin flavor";
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

    icons = {
      name = lib.mkOption {
        type = lib.types.str;
        default = if config.theme.catppuccin.flavor == "latte"
                  then "Papirus-Light"
                  else "Papirus-Dark";
        description = "Icon theme name";
      };
      package = lib.mkOption {
        type = lib.types.package;
        default = pkgs.catppuccin-papirus-folders.override {
          flavor = config.theme.catppuccin.flavor;
          accent = config.theme.catppuccin.accent;
        };
        description = "Icon theme package";
      };
    };

    cursor = {
      name = lib.mkOption {
        type = lib.types.str;
        default = if config.theme.catppuccin.flavor == "latte"
                  then "Breeze_Light"
                  else "breeze_cursors";
        description = "Cursor theme name";
      };
      package = lib.mkOption {
        type = lib.types.package;
        default = pkgs.kdePackages.breeze;
        description = "Cursor theme package";
      };
      size = lib.mkOption {
        type = lib.types.int;
        default = 24;
        description = "Cursor size";
      };
    };

    scale = lib.mkOption {
      type = lib.types.float;
      default = 1.0;
      description = "DPI/Monitor scale factor";
    };

    radius = {
      small = lib.mkOption {
        type = lib.types.int;
        default = 6;
        description = "Small border radius (progress bars, small elements)";
      };
      default = lib.mkOption {
        type = lib.types.int;
        default = 16;
        description = "Default border radius (windows, panels, notifications)";
      };
    };

    gaps = {
      inner = lib.mkOption {
        type = lib.types.int;
        default = 8;
        description = "Inner gaps (between windows)";
      };
      outer = lib.mkOption {
        type = lib.types.int;
        default = 16;
        description = "Outer gaps (screen edges)";
      };
    };

    border = {
      width = lib.mkOption {
        type = lib.types.int;
        default = 2;
        description = "Border width";
      };
    };

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
      description = "Runtime path to blurred wallpaper for SDDM (set by backgrounds module)";
    };
  };

  config = {
    catppuccin = {
      enable = true;
      flavor = config.theme.catppuccin.flavor;
      accent = config.theme.catppuccin.accent;
    };

    # Global dark preference for root apps (gparted, etc.)
    # /etc/gtk-*.0/ files are fallbacks; dconf system db provides defaults;
    # root's ~/.config/gtk-*.0/ is the most reliable since pkexec sets HOME=/root.
    environment.etc."gtk-2.0/gtkrc".text = lib.mkIf (config.theme.catppuccin.flavor != "latte") ''
      gtk-application-prefer-dark-theme=1
    '';
    environment.etc."gtk-3.0/settings.ini".text = lib.mkIf (config.theme.catppuccin.flavor != "latte") ''
      [Settings]
      gtk-application-prefer-dark-theme=1
    '';
    environment.etc."gtk-4.0/settings.ini".text = lib.mkIf (config.theme.catppuccin.flavor != "latte") ''
      [Settings]
      gtk-application-prefer-dark-theme=1
    '';

    programs.dconf = {
      enable = true;
      profiles.user.databases = [{
        settings."org/gnome/desktop/interface" = {
          color-scheme = if config.theme.catppuccin.flavor == "latte" then "prefer-light" else "prefer-dark";
        };
      }];
    };

    # Write dark theme settings directly into root's home (for pkexec apps)
    system.activationScripts.rootGtkDark.text = let
      isDark = config.theme.catppuccin.flavor != "latte";
      settingsIni = pkgs.writeText "gtk-dark-settings" ''
        [Settings]
        gtk-application-prefer-dark-theme=1
      '';
    in if isDark then ''
      mkdir -p /root/.config/gtk-3.0 /root/.config/gtk-4.0
      cp ${settingsIni} /root/.config/gtk-3.0/settings.ini
      cp ${settingsIni} /root/.config/gtk-4.0/settings.ini
    '' else ''
      rm -f /root/.config/gtk-3.0/settings.ini /root/.config/gtk-4.0/settings.ini
    '';

    # Qt theming for root (elevated apps like gparted, partition manager)
    # Only on Hyprland — KDE manages Qt theming itself
    system.activationScripts.rootQtDark = lib.mkIf (config.features.desktop.wm != "kde") {
      deps = [ ];
      text = let
        flavor = config.theme.catppuccin.flavor;
        isDark = flavor != "latte";
        iconName = config.theme.icons.name;
        kvantumTheme = "catppuccin-${flavor}-${config.theme.catppuccin.accent}";

        qt5ctConf = pkgs.writeText "qt5ct.conf" ''
          [Appearance]
          style=kvantum
          icon_theme=${iconName}
          color_scheme_path=
          custom_palette=false
        '';
        qt6ctConf = pkgs.writeText "qt6ct.conf" ''
          [Appearance]
          style=kvantum
          icon_theme=${iconName}
          color_scheme_path=
          custom_palette=false
        '';
        kvantumConf = pkgs.writeText "kvantum.kvconfig" ''
          [General]
          theme=${kvantumTheme}
        '';

        catppuccinKvantum = pkgs.catppuccin-kvantum.override {
          accent = config.theme.catppuccin.accent;
          variant = flavor;
        };
      in ''
        mkdir -p /root/.config/qt5ct /root/.config/qt6ct /root/.config/Kvantum
        cp ${qt5ctConf} /root/.config/qt5ct/qt5ct.conf
        cp ${qt6ctConf} /root/.config/qt6ct/qt6ct.conf
        cp ${kvantumConf} /root/.config/Kvantum/kvantum.kvconfig

        # Link Kvantum theme
        ln -sfn ${catppuccinKvantum}/share/Kvantum/${kvantumTheme} /root/.config/Kvantum/${kvantumTheme}
      '';
    };

    # Global Qt dark preference (root apps; user sessions override via qt6ct/KDE)
    # Skip under KDE — Plasma manages Qt theming itself
    qt = lib.mkIf (config.features.desktop.wm != "kde") {
      enable = true;
      platformTheme = "qt5ct";
      style = "kvantum";
    };

    environment.systemPackages = lib.mkIf (config.features.desktop.wm != "kde") (with pkgs; [
      libsForQt5.qt5ct
      kdePackages.qt6ct
      libsForQt5.qtstyleplugin-kvantum
      kdePackages.qtstyleplugin-kvantum
    ]);
  };
}
