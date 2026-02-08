{ config, pkgs, fonts, theme, locale, displays, lib, ... }:

let
  accent = config.catppuccin.accent;
  isLight = config.catppuccin.flavor == "latte";
  rawStyle = builtins.readFile ./waybar-style.scss;
  style = builtins.replaceStrings
    [ "@blue" "system_font" "separator_alpha" ]
    [ "@${accent}" fonts.ui (if isLight then "0.15" else "0.5") ]
    rawStyle;

  # Generate persistent-workspaces per monitor
  persistentWorkspaces = lib.listToAttrs (map (m: {
    name = m.name;
    value = m.workspaces;
  }) displays.monitors);
in
{
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
        on-click = "rofi -show drun";
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

      "tray".spacing = 10;

      "network" = {
        format-wifi = "{icon}";
        format-ethernet = "<span size='large'>󰈀</span>";
        format-disconnected = "<span size='large'>󰤭</span>";
        format-icons = [ "<span size='large'>󰤯</span>" "<span size='large'>󰤟</span>" "<span size='large'>󰤢</span>" "<span size='large'>󰤥</span>" "<span size='large'>󰤨</span>" ];
        tooltip-format = "{ifname} via {gwaddr}";
        tooltip-format-wifi = "{essid} ({signalStrength}%)";
        on-click = "kitty --title nmtui -e nmtui";
      };

      "bluetooth" = {
        format = "<span size='large'>󰂯</span>";
        format-connected = "<span size='large'>󰂱</span>";
        format-connected-battery = "<span size='large'>󰂱</span>";
        format-off = "<span size='large'>󰂲</span>";
        tooltip-format = "{controller_alias}\t{controller_address}";
        tooltip-format-connected = "{controller_alias}\t{controller_address}\n\n{device_enumerate}";
        tooltip-format-enumerate-connected = "{device_alias}\t{device_address}";
        on-click = "kitty --title bluetui -e bluetui";
      };

      "pulseaudio" = {
        format = "{icon}  {volume}%";
        format-muted = "<span size='large'>󰝟</span>  Stumm";
        format-icons = {
          default = [ "<span size='large'>󰕿</span>" "<span size='large'>󰖀</span>" "<span size='large'>󰕾</span>" ];
          headphone = "<span size='large'>󰋋</span>";
          headset = "<span size='large'>󰋎</span>";
        };
        on-click = "kitty --title pulsemixer -e pulsemixer";
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
        on-click = "powerprofilesctl set $(echo -e 'balanced\\npower-saver\\nperformance' | rofi -dmenu -p 'Power Profil')";
      };

      "clock" = {
        format = "{:L%a. %e. %b %H:%M}";
        locale = locale.language;
        tooltip = false;
      };
    };

    style = style;
  };
}
