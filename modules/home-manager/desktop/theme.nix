{ config, pkgs, lib, fonts, theme, features, input, ... }:

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

  isKde = features.desktop.wm == "kde";

  capitalize = s:
    (lib.toUpper (builtins.substring 0 1 s)) +
    (builtins.substring 1 (builtins.stringLength s) s);
  colorSchemeName = "Catppuccin ${capitalize flavor} ${capitalize accent}";
  colorSchemeId = "Catppuccin${capitalize flavor}${capitalize accent}";
  lookAndFeelId = "Catppuccin-${capitalize flavor}-${capitalize accent}";
  auroraeThemeId = "Catppuccin${capitalize flavor}-Modern";

  catppuccinKde = pkgs.catppuccin-kde.override {
    flavour = [ flavor ];
    accents = [ accent ];
  };

  # Patch Aurorae theme to use tiny buttons (upstream hardcodes 37x37)
  patchedAurorae = pkgs.runCommand "${auroraeThemeId}-tiny" {} ''
    cp -r ${catppuccinKde}/share/aurorae/themes/${auroraeThemeId} $out
    chmod +w $out $out/${auroraeThemeId}rc
    sed -i 's/ButtonHeight=37/ButtonHeight=28/' $out/${auroraeThemeId}rc
    sed -i 's/ButtonWidth=37/ButtonWidth=28/' $out/${auroraeThemeId}rc
  '';

  kwriteconfig = "${pkgs.kdePackages.kconfig}/bin/kwriteconfig6";

  pinnedLaunchersStr = lib.concatStringsSep "," config.kde.pinnedLaunchers;
  pinnedFavoritesStr = lib.concatStringsSep "," config.kde.pinnedFavorites;

  kickoffIcon = if isLight then "nix-snowflake" else "nix-snowflake-white";

  # Generic script to set a key in a Plasma widget's [Configuration][General]
  plasmaWidgetConfig = pkgs.writeTextFile {
    name = "plasma-widget-config";
    executable = true;
    text = ''
      #!${pkgs.python3}/bin/python3
      """Set a config key for a Plasma widget by plugin name.

      Usage: plasma-widget-config <config-file> <plugin> <key> <value>
      Finds the widget with the given plugin name and sets key=value
      in its [Configuration][General] section.
      """
      import sys, os

      config_path, plugin, key, value = sys.argv[1:5]
      if not os.path.isfile(config_path):
          sys.exit(0)

      with open(config_path) as f:
          lines = f.readlines()

      # Find the section header containing plugin=<plugin>
      widget_section = None
      current_section = ""
      for line in lines:
          s = line.strip()
          if s.startswith("["):
              current_section = s
          elif s == f"plugin={plugin}":
              widget_section = current_section
              break

      if not widget_section:
          sys.exit(1)

      target = widget_section[:-1] + "][Configuration][General]"
      target_exists = any(line.strip() == target for line in lines)

      if not target_exists:
          # Section missing (fresh KDE install) — append it
          with open(config_path, "a") as f:
              f.write(f"\n{target}\n{key}={value}\n")
          sys.exit(0)

      in_target = False
      found = False
      result = []
      for line in lines:
          s = line.strip()
          if s.startswith("["):
              if in_target and not found:
                  result.append(f"{key}={value}\n")
                  found = True
              in_target = (s == target)
          if in_target and s.startswith(f"{key}="):
              result.append(f"{key}={value}\n")
              found = True
              continue
          result.append(line)

      if in_target and not found:
          result.append(f"{key}={value}\n")

      with open(config_path, "w") as f:
          f.writelines(result)
    '';
  };
in
{
  options.kde = {
    pinnedLaunchers = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = "Pinned taskbar launchers for KDE (in order)";
    };
    pinnedFavorites = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = "Pinned Kickoff menu favorites for KDE (in order)";
    };
  };

  config = lib.mkMerge [
    # ── Default pinned launchers (autostart-style, based on features) ──────────
    {
      kde.pinnedLaunchers =
        [ "applications:firefox.desktop"
          "applications:org.kde.dolphin.desktop"
          "applications:kitty.desktop"
        ]
        ++ lib.optionals features.development.enable [
          "applications:code.desktop"
        ]
        ++ lib.optionals features.apps.enable [
          "applications:obsidian.desktop"
        ]
        ++ lib.optionals features.gaming.enable [
          "applications:steam.desktop"
        ]
        ++ lib.optionals features.apps.enable [
          "applications:discord.desktop"
          "applications:spotify.desktop"
        ];

      kde.pinnedFavorites =
        [ "applications:firefox.desktop"
          "applications:org.kde.dolphin.desktop"
          "applications:kitty.desktop"
        ]
        ++ lib.optionals features.development.enable [
          "applications:code.desktop"
        ]
        ++ lib.optionals features.apps.enable [
          "applications:obsidian.desktop"
        ]
        ++ lib.optionals features.gaming.enable [
          "applications:steam.desktop"
        ]
        ++ lib.optionals features.apps.enable [
          "applications:discord.desktop"
          "applications:spotify.desktop"
        ]
        ++ [
          "applications:systemsettings.desktop"
          "applications:org.kde.discover.desktop"
        ];
    }

    # ── Generic (all WMs) ───────────────────────────────────────────────────────
    {
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
    }

    # ── Tiling WMs (Hyprland etc.) — force Qt theming, hide window buttons ─────
    (lib.mkIf (!isKde) {
      gtk = {
        gtk3.extraConfig.gtk-decoration-layout = "";
        gtk4.extraConfig.gtk-decoration-layout = "";
      };

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
    })

    # ── KDE Plasma — Catppuccin KDE theming + wallpaper ─────────────────────────
    (lib.mkIf isKde {
      # GTK CSD apps (Nautilus etc.): match Mac-style button layout
      gtk = {
        gtk3.extraConfig.gtk-decoration-layout = "close,minimize,maximize:";
        gtk4.extraConfig.gtk-decoration-layout = "close,minimize,maximize:";
      };
      dconf.settings."org/gnome/desktop/wm/preferences".button-layout = "close,minimize,maximize:";

      # Symlink theme files to ~/.local/share/ where KDE discovers them
      xdg.dataFile = {
        "color-schemes/${colorSchemeId}.colors".source =
          "${catppuccinKde}/share/color-schemes/${colorSchemeId}.colors";
        "plasma/look-and-feel/${lookAndFeelId}".source =
          "${catppuccinKde}/share/plasma/look-and-feel/${lookAndFeelId}";
        "aurorae/themes/${auroraeThemeId}".source = patchedAurorae;
      };

      # Plasma-manager: declarative KDE Plasma configuration
      programs.plasma = {
        enable = true;

        # Workspace settings
        workspace = {
          lookAndFeel = lookAndFeelId;
          colorScheme = colorSchemeId;
          iconTheme = iconName;
          wallpaper = theme.wallpaper;
          cursor = {
            theme = cursorName;
            size = cursorSize;
          };
        };

        # Window decoration buttons (Mac-style: close, minimize, maximize on left)
        kwin.titlebarButtons = {
          left = [ "close" "minimize" "maximize" ];
          right = [];
        };

        # Low-level config for things without high-level API
        configFile = {
          # Breeze corner radius
          breezerc.Common.CornerRadius = theme.radius.default;
        };
      };

      # Autostart script to configure taskbar launchers and kickoff icon
      xdg.configFile."autostart/kde-launchers-setup.desktop".text = ''
        [Desktop Entry]
        Type=Application
        Name=KDE Launchers Setup
        Exec=${pkgs.writeShellScript "kde-launchers-setup" ''
          # Wait for Plasma to be ready
          timeout=30
          while [ $timeout -gt 0 ]; do
            if ${pkgs.kdePackages.qttools}/bin/qdbus org.kde.plasmashell /PlasmaShell >/dev/null 2>&1; then
              break
            fi
            sleep 0.5
            timeout=$((timeout - 1))
          done

          config="$HOME/.config/plasma-org.kde.plasma.desktop-appletsrc"
          if [ -f "$config" ]; then
            ${plasmaWidgetConfig} "$config" "org.kde.plasma.icontasks" "launchers" "${pinnedLaunchersStr}" \
              || ${plasmaWidgetConfig} "$config" "org.kde.plasma.taskmanager" "launchers" "${pinnedLaunchersStr}" \
              || true
            ${plasmaWidgetConfig} "$config" "org.kde.plasma.kickoff" "icon" "${kickoffIcon}" 2>/dev/null || true
            ${plasmaWidgetConfig} "$config" "org.kde.plasma.kickoff" "favorites" "${pinnedFavoritesStr}" 2>/dev/null || true
          fi
        ''}
        X-KDE-autostart-phase=2
        Hidden=false
      '';

      home.activation.applyKdeTheme = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        # Most settings are now managed by plasma-manager declaratively.
        # This activation script only handles complex/dynamic settings.

        # Lock screen wallpaper
        run ${kwriteconfig} --file kscreenlockerrc --group Greeter --group Wallpaper --key WallpaperPlugin "org.kde.image"
        run ${kwriteconfig} --file kscreenlockerrc --group Greeter --group Wallpaper --group org.kde.image --group General --key Image "file://${theme.wallpaper}"
        run ${kwriteconfig} --file kscreenlockerrc --group Greeter --group Wallpaper --group org.kde.image --group General --key PreviewImage "file://${theme.wallpaper}"

        # Window decoration: Breeze library and button size (buttons managed by plasma-manager)
        run ${kwriteconfig} --file kwinrc --group org.kde.kdecoration2 --key library org.kde.breeze
        run ${kwriteconfig} --file kwinrc --group org.kde.kdecoration2 --key theme Breeze
        run ${kwriteconfig} --file kwinrc --group org.kde.kdecoration2 --key ButtonSize "Tiny"

        # Natural scroll — per-device via Libinput groups (Plasma 6 Wayland format)
        # KWin reads: [Libinput][vendor_decimal][product_decimal][device_name]
        ${pkgs.gawk}/bin/awk '
          /^I:/ { vendor=""; product=""
            if (match($0, /Vendor=([0-9a-fA-F]+)/, m)) vendor=strtonum("0x" m[1])
            if (match($0, /Product=([0-9a-fA-F]+)/, m)) product=strtonum("0x" m[1])
          }
          /^N:/ { gsub(/^N: Name="/, ""); gsub(/"$/, ""); name=$0 }
          /^H:.*mouse|^H:.*event/ {
            if (vendor != "" && product != "" && name != "") {
              if (tolower(name) ~ /touchpad/) {
                print vendor "\t" product "\t" name "\ttouchpad"
              } else if (tolower(name) ~ /mouse|pointer|razer|logitech|steelseries/) {
                print vendor "\t" product "\t" name "\tmouse"
              }
            }
          }
        ' /proc/bus/input/devices | while IFS=$'\t' read -r vid pid dname dtype; do
          if [ "$dtype" = "touchpad" ]; then
            scroll="${lib.boolToString input.touchpad.naturalScroll}"
          else
            scroll="${lib.boolToString input.mouse.naturalScroll}"
          fi
          run ${kwriteconfig} --file kcminputrc \
            --group Libinput --group "$vid" --group "$pid" --group "$dname" \
            --key NaturalScroll "$scroll"
        done

        # Tell running KWin to reload decoration settings (if KWin is running)
        ${pkgs.kdePackages.qttools}/bin/qdbus org.kde.KWin /KWin reconfigure 2>/dev/null || true
      '';
    })
  ];
}
