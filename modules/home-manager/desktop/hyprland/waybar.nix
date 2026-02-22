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
#
# Styling:
# - Uses waybar-style.scss with template variables
# - @blue → @${accent} (theme accent color)
# - system_font → fonts.ui (UI font name)
# - separator_alpha → 0.5 for dark, 0.15 for light themes

{ config, pkgs, fonts, theme, locale, displays, lib, ... }:

let
  # Theme variables
  inherit (config.catppuccin) accent;
  isLight = config.catppuccin.flavor == "latte";

  # Load and customize SCSS styling
  rawStyle = builtins.readFile ./waybar-style.scss;
  style = builtins.replaceStrings
    [ "@blue" "system_font" "separator_alpha" ]
    [ "@${accent}" fonts.ui (if isLight then "0.15" else "0.5") ]
    rawStyle;

  # Generate persistent-workspaces configuration per monitor
  # Example: { "DP-1" = [1 2 3]; "HDMI-A-1" = [4 5 6]; }
  persistentWorkspaces = lib.listToAttrs (map (m: {
    inherit (m) name;
    value = m.workspaces;
  }) displays.monitors);

  # Reload script (used by Super+Shift+R keybinding)
  reload = pkgs.writeShellScript "waybar-reload" ''
    pkill waybar
    uwsm-app -- waybar &
  '';
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

  #===========================
  # Configuration
  #===========================

  config = {
    catppuccin.waybar.mode = "createLink";

    programs.waybar = {
    enable = true;
    systemd.enable = true;

    settings.mainBar = {
      layer = "top";
      position = "top";
      height = theme.gaps.outer;
      spacing = 0;
      margin-top = theme.gaps.inner + 4;
      margin-left = theme.gaps.outer;
      margin-right = theme.gaps.outer;

      modules-left = [ "custom/launcher" "hyprland/workspaces" "hyprland/window" ];
      modules-center = [ ];
      modules-right = [ "tray" "network" "bluetooth" "pulseaudio" "battery" "clock" ];

      "custom/launcher" = {
        format = "<span size='x-large' rise='-2000'>󱄅</span>";
        on-click = "${config.rofi.toggle}";
        tooltip = false;
      };

      "hyprland/workspaces" = {
        format = "";
        all-outputs = false;
        persistent-workspaces = persistentWorkspaces;
        on-click = "activate";
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
        spacing = 10;
        icon-size = 16;
      };

      "network" = {
        format-wifi = "{icon}";
        format-ethernet = "<span size='large'>󰈀</span>";
        format-disconnected = "<span size='large'>󰤭</span>";
        format-icons = [ "<span size='large'>󰤯</span>" "<span size='large'>󰤟</span>" "<span size='large'>󰤢</span>" "<span size='large'>󰤥</span>" "<span size='large'>󰤨</span>" ];
        tooltip-format = "{ifname} via {gwaddr}";
        tooltip-format-wifi = "{essid} ({signalStrength}%)";
        on-click = "${config.terminal.exec} impala -e impala";
      };

      "bluetooth" = {
        format = "<span size='large'>󰂯</span>";
        format-connected = "<span size='large'>󰂱</span>";
        format-connected-battery = "<span size='large'>󰂱</span>";
        format-off = "<span size='large'>󰂲</span>";
        tooltip-format = "{controller_alias}\t{controller_address}";
        tooltip-format-connected = "{controller_alias}\t{controller_address}\n\n{device_enumerate}";
        tooltip-format-enumerate-connected = "{device_alias}\t{device_address}";
        on-click = "${config.terminal.exec} bluetui -e bluetui";
      };

      "pulseaudio" = {
        format = "{icon}  <span rise='1500'>{volume}%</span>";
        format-muted = "<span size='large'>󰝟</span>  <span rise='1500'>Stumm</span>";
        format-icons = {
          default = [ "<span size='large'>󰕿</span>" "<span size='large'>󰖀</span>" "<span size='large'>󰕾</span>" ];
          headphone = "<span size='large'>󰋋</span>";
          headset = "<span size='large'>󰋎</span>";
        };
        on-click = "${config.terminal.exec} wiremix -e wiremix";
        tooltip-format = "{desc}";
      };

      "battery" = {
        states = { warning = 30; critical = 15; };
        format = "{icon}  {capacity}%";
        format-charging = "<span size='large'>󰂄</span>  {capacity}%";
        format-plugged = "<span size='large'>󰚥</span>  {capacity}%";
        format-icons = [
          "<span size='large'>󰂎</span>" "<span size='large'>󰁺</span>" "<span size='large'>󰁻</span>"
          "<span size='large'>󰁼</span>" "<span size='large'>󰁽</span>" "<span size='large'>󰁾</span>"
          "<span size='large'>󰁿</span>" "<span size='large'>󰂀</span>" "<span size='large'>󰂁</span>"
          "<span size='large'>󰂂</span>" "<span size='large'>󰁹</span>"
        ];
        on-click = "${config.rofi.powerProfile}";
      };

      "clock" = {
        format = "{:L%a. %H:%M}";
        locale = locale.language;
        tooltip = false;
      };
    };

      inherit style;
    };
  };
}
