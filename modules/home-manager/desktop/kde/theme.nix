# KDE Plasma Theme Configuration
#
# This module configures KDE Plasma-specific theming:
# - Catppuccin color scheme and look-and-feel
# - Wallpaper (desktop and lock screen)
# - Window decorations (Breeze with Mac-style buttons)
# - Taskbar pinned launchers
# - Kickoff menu icon
# - Natural scroll per-device configuration
#
# Common theming (GTK, cursor, icons, pinned apps):
# - See common/theme.nix

{ config, pkgs, lib, theme, input, ... }:

let
  flavor = theme.catppuccin.flavor;
  accent = theme.catppuccin.accent;
  isLight = flavor == "latte";
  iconName = theme.icons.name;
  cursorName = theme.cursor.name;
  cursorSize = theme.cursor.size;

  # Helper function: Capitalize first letter
  # Example: "mocha" → "Mocha"
  capitalize = s:
    (lib.toUpper (builtins.substring 0 1 s)) +
    (builtins.substring 1 (builtins.stringLength s) s);

  # KDE theme names (Plasma-specific)
  # Examples: "Catppuccin Mocha Mauve", "CatppuccinMochaMauve"
  colorSchemeName = "Catppuccin ${capitalize flavor} ${capitalize accent}";
  colorSchemeId = "Catppuccin${capitalize flavor}${capitalize accent}";
  lookAndFeelId = "Catppuccin-${capitalize flavor}-${capitalize accent}";
  auroraeThemeId = "Catppuccin${capitalize flavor}-Modern";

  # KDE theme package
  catppuccinKde = pkgs.catppuccin-kde.override {
    flavour = [ flavor ];
    accents = [ accent ];
  };

  # ============================================================================
  # PATCHED AURORAE THEME
  # ============================================================================
  # Why: Upstream Catppuccin KDE theme uses 37x37 window buttons (too large)
  #
  # Solution: Patch the theme to use 28x28 buttons (matches macOS/Windows)
  #
  # How: Copy theme from Nix store and sed the ButtonHeight/ButtonWidth values
  patchedAurorae = pkgs.runCommand "${auroraeThemeId}-tiny" {} ''
    cp -r ${catppuccinKde}/share/aurorae/themes/${auroraeThemeId} $out
    chmod +w $out $out/${auroraeThemeId}rc
    sed -i 's/ButtonHeight=37/ButtonHeight=28/' $out/${auroraeThemeId}rc
    sed -i 's/ButtonWidth=37/ButtonWidth=28/' $out/${auroraeThemeId}rc
  '';

  # KDE configuration tools
  kwriteconfig = "${pkgs.kdePackages.kconfig}/bin/kwriteconfig6";

  # Pinned applications for KDE taskbar
  # Format: "applications:firefox.desktop,applications:kitty.desktop,..."
  pinnedLaunchersStr = lib.concatStringsSep "," (map (app: "applications:${app}.desktop") config.desktop.pinnedApps);

  # Kickoff menu icon (KDE start menu)
  kickoffIcon = if isLight then "nix-snowflake" else "nix-snowflake-white";

  # ============================================================================
  # PLASMA WIDGET CONFIGURATION SCRIPT
  # ============================================================================
  # Why: KDE's plasma-org.kde.plasma.desktop-appletsrc uses dynamic widget IDs
  # that change on every fresh install, making declarative config impossible.
  #
  # Problem: Can't set taskbar launchers or kickoff icon declaratively because
  # we don't know the widget ID in advance.
  #
  # Solution: Python script that finds widgets by plugin name and modifies
  # their config dynamically.
  #
  # How it works:
  # 1. Parse plasma-org.kde.plasma.desktop-appletsrc (INI-like format)
  # 2. Find section containing "plugin=<plugin-name>"
  # 3. Modify [<section>][Configuration][General]<key>=<value>
  # 4. Write back to file
  #
  # Used for:
  # - Setting taskbar pinned launchers (org.kde.plasma.icontasks)
  # - Setting kickoff menu icon (org.kde.plasma.kickoff)
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
  #===========================
  # Configuration
  #===========================

  config = {
    # GTK CSD apps (Nautilus etc.): match Mac-style button layout
    # (close, minimize, maximize on left side)
    gtk = {
      gtk3.extraConfig.gtk-decoration-layout = "close,minimize,maximize:";
      gtk3.extraCss = "* { -gtk-icon-style: symbolic; }";
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

    programs.plasma = {
      enable = true;

      # Workspace settings
      workspace = {
        lookAndFeel = lookAndFeelId;
        colorScheme = colorSchemeId;
        iconTheme = iconName;
        wallpaper = theme.wallpaperPath;
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

      # Disable hot corners
      kwin.edgeBarrier = 0;
      kwin.cornerBarrier = false;

      # KRunner (search) on Super+Space
      shortcuts."org.kde.krunner.desktop"._launch = "Meta+Space";
      shortcuts.kwin.Overview = [];

      # Low-level config for things without high-level API
      configFile = {
        # Breeze corner radius
        breezerc.Common.CornerRadius = theme.radius.default;
        # Disable screen edges (hot corners for desktop grid, etc.)
        kwinrc.Effect-overview.BorderActivate = 9;
        kwinrc.Effect-windowview.BorderActivate = 9;
        kwinrc.ElectricBorders.TopLeft = "None";
        kwinrc.ElectricBorders.TopRight = "None";
        kwinrc.ElectricBorders.BottomLeft = "None";
        kwinrc.ElectricBorders.BottomRight = "None";
        kwinrc.ElectricBorders.Top = "None";
        kwinrc.ElectricBorders.Bottom = "None";
        kwinrc.ElectricBorders.Left = "None";
        kwinrc.ElectricBorders.Right = "None";
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
      run ${kwriteconfig} --file kscreenlockerrc --group Greeter --group Wallpaper --group org.kde.image --group General --key Image "file://${theme.wallpaperPath}"
      run ${kwriteconfig} --file kscreenlockerrc --group Greeter --group Wallpaper --group org.kde.image --group General --key PreviewImage "file://${theme.wallpaperPath}"

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
  };
}
