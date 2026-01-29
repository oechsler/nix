{ config, pkgs, ... }:

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
        modules-right = [ "tray" "network" "bluetooth" "battery" "clock" ];

        # Launcher
        "custom/launcher" = {
          format = "rofi";
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
          format-wifi = "  {essid}";
          format-ethernet = "  {ifname}";
          format-disconnected = "  Disconnected";
          tooltip-format = "{ifname} via {gwaddr}";
          tooltip-format-wifi = "{essid} ({signalStrength}%)";
        };

        # Bluetooth
        "bluetooth" = {
          format = " {status}";
          format-connected = " {device_alias}";
          format-connected-battery = " {device_alias} {device_battery_percentage}%";
          tooltip-format = "{controller_alias}\t{controller_address}";
          tooltip-format-connected = "{controller_alias}\t{controller_address}\n\n{device_enumerate}";
          tooltip-format-enumerate-connected = "{device_alias}\t{device_address}";
          on-click = "blueberry";
        };

        # Battery
        "battery" = {
          states = {
            warning = 30;
            critical = 15;
          };
          format = "{icon} {capacity}%";
          format-charging = " {capacity}%";
          format-plugged = " {capacity}%";
          format-icons = ["" "" "" "" ""];
        };

        # Clock
        "clock" = {
          format = "{:L%a. %H:%M}";
          locale = "de_DE.utf8";
          tooltip = false;
        };
      };
    };

    style = builtins.readFile ./waybar-style.scss;
  };
}
