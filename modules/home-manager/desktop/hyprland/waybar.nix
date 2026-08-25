# Waybar Configuration (Hyprland Status Bar)
#
# This module configures waybar as the status bar for Hyprland.
#
# Modules (left to right):
# - Left: Launcher icon, workspaces, active window title
# - Center: (empty)
# - Right: System tray, network, bluetooth, volume, battery, clock
#
# Features:
# - Per-monitor workspace support
# - Catppuccin theme integration
# - Custom SCSS styling with theme variables
# - Transparent background (alpha 0.85)
# - Icons from Nerd Fonts
# - Papirus tray icons with customizable mappings (Hyprland only, ignored on KDE)
#
# Tray Icons:
# - Default mappings use Papirus-Dark icons for Steam, Nextcloud, Mumble, Vesktop, Trayscale
# - Mappings are feature-gated (only active apps get their icons)
# - Customize or add mappings via: waybar.tray.icons = { "AppId" = "icon-name"; };
# - This option has no effect on KDE (Plasma manages its own tray icons)
#
# Styling:
# - Uses waybar-style.scss with template variables
# - @blue → @${accent} (theme accent color)
# - system_font → fonts.ui (UI font name)
# - separator_alpha → 0.5 for dark, 0.15 for light themes

{
  config,
  pkgs,
  fonts,
  theme,
  locale,
  i18n,
  displays,
  features,
  lib,
  ...
}:

let
  # Theme variables
  inherit (config.catppuccin) accent;
  isLight = config.catppuccin.flavor == "latte";
  papirusText = if isLight then "#444444" else "#dfdfdf";
  # Small Waybar-specific refinement while staying tied to shared theme spacing.
  fineSpacing = theme.spacing.compact / 2;
  iconSize = fonts.uiPixelSize;
  iconOpticalSpacing = builtins.floor (iconSize / 7);

  # Load and customize SCSS styling
  rawStyle = builtins.readFile ./waybar-style.scss;
  style =
    builtins.replaceStrings
      [
        "@blue"
        "papirus_text"
        "system_font"
        "separator_alpha"
        "container_alpha"
        "inactive_alpha"
        "selected_alpha"
        "highlight_alpha"
        "subtle_alpha"
        "window_radius"
        "control_spacing"
        "compact_spacing"
        "vertical_spacing"
        "workspace_vertical_spacing"
        "workspace_horizontal_spacing"
        "module_spacing"
        "content_spacing"
        "window_spacing"
        "network_right_spacing"
        "icon_size"
        "launcher_width"
        "bar_height"
        "outer_spacing"
        "ui_font_size"
        "launcher_font_size"
        "border_width"
      ]
      [
        "@${accent}"
        papirusText
        fonts.ui
        (if isLight then "0.15" else "0.5")
        (lib.strings.floatToString theme.alpha.container)
        (lib.strings.floatToString theme.alpha.inactive)
        (lib.strings.floatToString theme.alpha.selected)
        (lib.strings.floatToString theme.alpha.highlight)
        (lib.strings.floatToString theme.alpha.subtle)
        "${toString theme.radius.default}px"
        "${toString theme.spacing.control}px"
        "${toString theme.spacing.compact}px"
        "${toString theme.spacing.vertical}px"
        "${toString theme.spacing.workspace}px"
        "${toString theme.spacing.workspaceHorizontal}px"
        "${toString theme.spacing.module}px"
        "${toString theme.spacing.content}px"
        "${toString (theme.spacing.module + fineSpacing)}px"
        "${toString (theme.spacing.module + (iconOpticalSpacing * 2))}px"
        "${toString iconSize}px"
        "${toString theme.sizes.launcher}px"
        "${toString theme.gaps.outer}px"
        "${toString theme.gaps.outer}px"
        "${toString fonts.uiPixelSize}px"
        "${toString (fonts.uiPixelSize + 6)}px"
        "${toString theme.border.width}px"
      ]
      rawStyle;
  themeTrigger = pkgs.writeText "waybar-theme-trigger" (
    builtins.toJSON {
      inherit (theme)
        alpha
        border
        gaps
        radius
        spacing
        ;
      inherit (config.catppuccin) accent flavor;
    }
  );

  # Generate persistent-workspaces configuration per monitor.
  # The "*" fallback prevents Waybar from using its own default for unknown outputs.
  # Example: { "*" = [1 2 3 4]; "DP-1" = [1 2 3 4]; "HDMI-A-1" = [5 6 7 8]; }
  defaultWorkspaces = lib.range 1 displays.defaultWorkspaceCount;
  persistentWorkspaces = {
    "*" = defaultWorkspaces;
  }
  // lib.listToAttrs (
    map (m: {
      inherit (m) name;
      value = if m.workspaces == [ ] then defaultWorkspaces else m.workspaces;
    }) displays.monitors
  );

  defaultTrayIcons =
    lib.optionalAttrs features.gaming.enable {
      steam = "steam_tray_mono";
    }
    // lib.optionalAttrs features.apps.enable {
      Mumble = "mumble-indicator";
      "Proton Pass_status_icon_1" = "dialog-password-panel";
      vesktop_status_icon_1 = "discord-tray";
    }
    // lib.optionalAttrs features.tailscale.enable (
      lib.listToAttrs [
        {
          name = "dev.deedles.Trayscale";
          value = "network-vpn";
        }
      ]
    );

  # Reload script (used by Super+Shift+R keybinding)
  reload = pkgs.writeShellScript "waybar-reload" ''
    pkill waybar
    uwsm-app -- waybar &
  '';

  waybar = pkgs.waybar.overrideAttrs (old: {
    patches = (old.patches or [ ]) ++ [ ./waybar-sni-custom-icon.patch ];

    postPatch = (old.postPatch or "") + ''
      substituteInPlace src/modules/hyprland/workspace.cpp \
        --replace-fail \
          'm_ipc.getSocket1Reply("dispatch workspace " + std::to_string(id()));' \
          'm_ipc.getSocket1Reply("dispatch hl.dsp.focus({ workspace = " + std::to_string(id()) + " })");'
    '';
  });

in
{
  #===========================
  # Options
  #===========================

  options.waybar.reload = lib.mkOption {
    type = lib.types.path;
    default = reload;
    readOnly = true;
    description = "Script to reload waybar (pkill + restart)";
  };

  options.waybar.tray.icons = lib.mkOption {
    type = lib.types.attrsOf lib.types.str;
    default = { };
    description = "Additional or overriding StatusNotifierItem Id to Papirus icon name mappings";
  };

  #===========================
  # Configuration
  #===========================

  config = {
    catppuccin.waybar.mode = "createLink";

    programs.waybar = {
      enable = true;
      systemd.enable = true;
      package = waybar;

      settings.mainBar = {
        layer = "top";
        position = "top";
        height = theme.gaps.outer;
        spacing = 0;
        margin-top = theme.gaps.inner + 4;
        margin-left = theme.gaps.outer;
        margin-right = theme.gaps.outer;

        modules-left = [
          "custom/launcher"
          "hyprland/workspaces"
          "hyprland/window"
        ];
        modules-center = [ ];
        modules-right = [
          "tray"
          "network"
        ]
        ++ lib.optionals features.bluetooth.enable [ "bluetooth" ]
        ++ [
          "custom/power-profile"
          "battery"
          "pulseaudio"
          "clock"
        ];

        "custom/launcher" = {
          format = "󱄅";
          on-click = "${config.rofi.toggle}";
          tooltip = false;
        };

        "hyprland/workspaces" = {
          format = "";
          all-outputs = false;
          persistent-workspaces = persistentWorkspaces;
          cursor = true;
        };

        "hyprland/window" = {
          format = "{title}";
          max-length = 50;
          separate-outputs = true;
          icon = true;
          icon-size = 16;
          rewrite = {
            "" = builtins.baseNameOf config.xdg.userDirs.desktop;
            "(.*) - (.*)" = "$2";
            "(.*) — (.*)" = "$2";
            "(.*) – (.*)" = "$2";
          };
        };

        "tray" = {
          spacing = theme.spacing.module + fineSpacing;
          icon-size = iconSize;
          icons = defaultTrayIcons // config.waybar.tray.icons;
        };

        "network" = {
          format-wifi = "{icon}";
          format-ethernet = "<span size='large'>󰈀</span>";
          format-linked = "<span size='large'>󰈀</span>";
          format-disconnected = "<span size='large'>󰤭</span>";
          format-icons = [
            "<span size='large'>󰤯</span>"
            "<span size='large'>󰤟</span>"
            "<span size='large'>󰤢</span>"
            "<span size='large'>󰤥</span>"
            "<span size='large'>󰤨</span>"
          ];
          tooltip-format = "{gwaddr}";
          tooltip-format-wifi = "{essid} ({signalStrength}%)";
          on-click = lib.mkIf features.wifi.enable "${config.terminal.exec} impala";
        };

        "bluetooth" = {
          format = "<span size='large'>󰂯</span>";
          format-connected = "<span size='large'>󰂱</span>";
          format-connected-battery = "<span size='large'>󰂱</span>";
          format-off = "<span size='large'>󰂲</span>";
          tooltip-format = "{controller_alias}\t{controller_address}";
          tooltip-format-connected = "{controller_alias}\t{controller_address}\n\n{device_enumerate}";
          tooltip-format-enumerate-connected = "{device_alias}\t{device_address}";
          on-click = "${config.terminal.exec} bluetui";
        };

        "pulseaudio" = {
          format = "{icon}  <span rise='1500'>{volume:3}%</span>";
          format-muted = "<span size='large'>󰝟</span>  <span rise='1500'>${i18n.translate "Muted" "Stumm"}</span>";
          format-icons = {
            default = [
              "<span size='large'>󰕿</span>"
              "<span size='large'>󰖀</span>"
              "<span size='large'>󰕾</span>"
            ];
            headphone = "<span size='large'>󰋋</span>";
            headset = "<span size='large'>󰋎</span>";
          };
          on-click = "${config.terminal.exec} wiremix";
          tooltip-format = "{desc}";
        };

        "custom/power-profile" = {
          exec = pkgs.writeShellScript "waybar-power-profile" ''
            profile=$(${pkgs.power-profiles-daemon}/bin/powerprofilesctl get)
            case "$profile" in
               performance) echo '{"text": "<span size=\"large\">󱐋</span>", "tooltip": "${i18n.translate "Performance" "Leistung"}"}' ;;
              power-saver)  echo '{"text": "<span size=\"large\">󰌪</span>", "tooltip": "${i18n.translate "Power saver" "Energiesparen"}"}' ;;
               *)             echo '{"text": "<span size=\"large\">󰾆</span>", "tooltip": "${i18n.translate "Balanced" "Ausgewogen"}"}' ;;
            esac
          '';
          exec-if = "command -v powerprofilesctl";
          return-type = "json";
          interval = 5;
          on-click = "${config.rofi.powerProfile}";
          tooltip = true;
        };

        "battery" = {
          states = {
            warning = 30;
            critical = 15;
          };
          format = "{icon}  {capacity}%";
          format-charging = "<span size='large'>󰂄</span>  {capacity}%";
          format-plugged = "<span size='large'>󰚥</span>  {capacity}%";
          format-icons = [
            "<span size='large'>󰂎</span>"
            "<span size='large'>󰁺</span>"
            "<span size='large'>󰁻</span>"
            "<span size='large'>󰁼</span>"
            "<span size='large'>󰁽</span>"
            "<span size='large'>󰁾</span>"
            "<span size='large'>󰁿</span>"
            "<span size='large'>󰂀</span>"
            "<span size='large'>󰂁</span>"
            "<span size='large'>󰂂</span>"
            "<span size='large'>󰁹</span>"
          ];
        };

        "clock" = {
          format = "{:L%a. %H:%M}";
          locale = locale.language;
          tooltip = false;
        };
      };

      inherit style;
    };

    systemd.user.services.waybar = {
      Unit.X-Restart-Triggers = [
        config.theme.catppuccin.restartTrigger
        themeTrigger
      ];
    };
  };
}
