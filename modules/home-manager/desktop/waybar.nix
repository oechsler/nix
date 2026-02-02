{ config, pkgs, fonts, ... }:

let
  accent = config.catppuccin.accent;

  rawStyle = builtins.readFile ./waybar-style.scss;
  style = builtins.replaceStrings
    [ "@blue" "system_font" ]
    [ "@${accent}" fonts.monospace ]
    rawStyle;
in
{
  catppuccin.waybar.mode = "createLink";

  programs.waybar = {
    enable = true;
    systemd.enable = true;

    settings = {
      mainBar = {
        layer = "top";
        position = "top";
        height = 16;
        spacing = 0;
        margin-top = 12;
        margin-left = 16;
        margin-right = 16;

        # Layout
        modules-left = [ "custom/launcher" "hyprland/workspaces" "hyprland/window" ];
        modules-center = [ ];
        modules-right = [ "tray" "network" "bluetooth" "pulseaudio" "battery" "clock" ];

        # Launcher (Nix Snowflake)
        "custom/launcher" = {
          format = "<span size='x-large' rise='-2000'>󱄅</span>";
          on-click = "rofi -show drun";
          tooltip = false;
        };

        # Workspaces
        "hyprland/workspaces" = {
          format = "";
          persistent-workspaces = {
            "1" = [ ];
            "2" = [ ];
            "3" = [ ];
            "4" = [ ];
          };
          on-click = "activate";
        };

        # Active window title
        "hyprland/window" = {
          format = "{title}";
          max-length = 50;
          separate-outputs = true;
          icon = true;
          icon-size = 16;
          rewrite = {
            "" = "Schreibtisch";
            "(.*) - (.*)" = "$2";
            "(.*) — (.*)" = "$2";
            "(.*) – (.*)" = "$2";
          };
        };

        # System tray
        "tray" = {
          spacing = 10;
        };

        # Network
        "network" = {
          format-wifi = "{icon}  {essid}";
          format-ethernet = "<span size='large'>󰈀</span>  {ifname}";
          format-disconnected = "<span size='large'>󰤭</span>  Getrennt";
          format-icons = [ "<span size='large'>󰤯</span>" "<span size='large'>󰤟</span>" "<span size='large'>󰤢</span>" "<span size='large'>󰤥</span>" "<span size='large'>󰤨</span>" ];
          tooltip-format = "{ifname} via {gwaddr}";
          tooltip-format-wifi = "{essid} ({signalStrength}%)";
        };

        # Bluetooth
        "bluetooth" = {
          format = "<span size='large'>󰂯</span>  An";
          format-connected = "<span size='large'>󰂱</span>  {num_connections} verbunden";
          format-connected-battery = "<span size='large'>󰂱</span>  {num_connections} verbunden";
          format-off = "<span size='large'>󰂲</span>  Aus";
          tooltip-format = "{controller_alias}\t{controller_address}";
          tooltip-format-connected = "{controller_alias}\t{controller_address}\n\n{device_enumerate}";
          tooltip-format-enumerate-connected = "{device_alias}\t{device_address}";
          on-click = "blueberry";
        };

        # Audio
        "pulseaudio" = {
          format = "{icon}  {volume}%";
          format-muted = "<span size='large'>󰝟</span>  Stumm";
          format-icons = {
            default = [ "<span size='large'>󰕿</span>" "<span size='large'>󰖀</span>" "<span size='large'>󰕾</span>" ];
            headphone = "<span size='large'>󰋋</span>";
            headset = "<span size='large'>󰋎</span>";
          };
          on-click = "pavucontrol";
          tooltip-format = "{desc}";
        };

        # Battery
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

        # Clock
        "clock" = {
          format = "{:L%a. %d. %b %H:%M}";
          locale = "de_DE.utf8";
          tooltip = false;
        };
      };
    };

    style = style;
  };
}
