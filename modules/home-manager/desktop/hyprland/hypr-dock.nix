# Hypr Dock Configuration (Hyprland Application Dock)
#
# This module configures hypr-dock as the application dock for Hyprland.
#
# Features:
# - Pinned applications (from desktop.pinnedApps)
# - Catppuccin theme integration
# - Transparent background (alpha 0.85)
# - Auto-start with graphical session
# - Window previews (disabled by default)
#
# Configuration:
# - Position: Bottom center
# - Icon size: 36px
# - Margin: theme.gaps.outer (matches waybar)
# - Border radius: theme.radius.default
# - Border: 2px accent color
#
# Toggle:
#   features.desktop.dock.enable = true;  (default: true)

{ config, pkgs, lib, theme, features, ... }:

let
  # Extract Catppuccin palette colors for theme
  palette = (lib.importJSON "${config.catppuccin.sources.palette}/palette.json").${config.catppuccin.flavor}.colors;
  accentHex = palette.${config.catppuccin.accent}.hex;
  baseHex = palette.base.hex;
  surfaceHex = palette.surface0.hex;
  textHex = palette.text.hex;
in
{
  #===========================
  # Configuration
  #===========================

  config = lib.mkIf features.desktop.dock.enable {

    #---------------------------
    # 1. Package
    #---------------------------
    home.packages = [ pkgs.hypr-dock ];

    #---------------------------
    # 2. Systemd Service
    #---------------------------
    # Auto-start hypr-dock with graphical session
    systemd.user.services.hypr-dock = {
      Unit = {
        Description = "Hypr Dock";
        PartOf = [ "graphical-session.target" ];
      };
      Service = {
        ExecStart = "${pkgs.hypr-dock}/bin/hypr-dock";
        Restart = "on-failure";
        RestartSec = 2;
      };
      Install.WantedBy = [ "graphical-session.target" ];
    };

    #---------------------------
    # 3. Dock Configuration
    #---------------------------
    # Main dock settings (position, size, margins)
    xdg.configFile = {
      "hypr-dock/config.jsonc".text = builtins.toJSON {
        CurrentTheme = "catppuccin";
        IconSize = 36;
        Layer = "exclusive-bottom";
        Position = "bottom";
        SystemGapUsed = "true";
        Margin = theme.gaps.outer;
        ContextPos = 5;
        Preview = "none";  # Disable window previews
      };

      #---------------------------
      # 4. Pinned Applications
      #---------------------------
      # Apps shown in dock (from desktop.pinnedApps)
      "hypr-dock/pinned.json".text = builtins.toJSON {
        Pinned = config.desktop.pinnedApps;
      };

      #---------------------------
      # 5. Catppuccin Theme
      #---------------------------
      # Theme configuration (generated from Catppuccin palette)
      "hypr-dock/themes/catppuccin/catppuccin.jsonc".text = builtins.toJSON {
        Blur = "true";
        Spacing = 5;
        PreviewStyle = {
          Size = 120;
          BorderRadius = theme.radius.small;
          Padding = 10;
        };
      };
      "hypr-dock/themes/catppuccin/style.css".text = ''
      window {
        background-color: transparent;
      }

      #app {
        background-color: alpha(${baseHex}, 0.85);
        border-radius: ${toString theme.radius.default}px;
        border: 2px solid ${accentHex};
        padding: 6px;
      }

      button {
        background-color: rgba(0, 0, 0, 0);
        padding: 5px;
        margin: 1px;
        border-radius: ${toString theme.radius.default}px;
        border: none;
        transition: all 50ms ease;
      }

      button:hover {
        background-color: alpha(${accentHex}, 0.15);
      }

      button:active {
        background-color: alpha(${accentHex}, 0.3);
      }

      #menu-item {
        padding: 3px;
        padding-left: 0;
      }

      menu {
        background-color: alpha(${baseHex}, 0.92);
        border: 2px solid alpha(${accentHex}, 0.5);
        border-radius: ${toString theme.radius.small}px;
        box-shadow: 0 4px 12px rgba(0, 0, 0, 0.3);
        outline: none;
        background-image: none;
        padding: 4px;
      }

      menuitem {
        color: ${textHex};
        padding: 4px 8px;
        border-radius: ${toString theme.radius.small}px;
        transition: all 0.15s ease;
      }

      menuitem:hover {
        background-color: alpha(${accentHex}, 0.2);
        color: ${accentHex};
      }

      #pv-item {
        background-color: alpha(${surfaceHex}, 0.8);
        transition: all 0.2s ease-out;
        border-radius: ${toString theme.radius.small}px;
        border: 1px solid alpha(${accentHex}, 0.2);
      }

      #pv-item.hover {
        background-color: alpha(${accentHex}, 0.15);
        border-color: alpha(${accentHex}, 0.5);
      }
    '';

      # Point indicators (dots under icons) in accent color
      "hypr-dock/themes/catppuccin/point/0.svg".text = ''
      <svg width="48" height="8" viewBox="0 0 12.7 2.1167" xmlns="http://www.w3.org/2000/svg"></svg>
    '';
      "hypr-dock/themes/catppuccin/point/1.svg".text = ''
        <svg width="48" height="9" viewBox="0 0 12.7 2.3812" xmlns="http://www.w3.org/2000/svg">
          <circle cx="6.35" cy="1.0583" r=".9388" fill="${accentHex}"/>
        </svg>
      '';
      "hypr-dock/themes/catppuccin/point/2.svg".text = ''
        <svg width="48" height="9" viewBox="0 0 12.7 2.3812" xmlns="http://www.w3.org/2000/svg">
          <g fill="${accentHex}"><circle cx="4.6917" cy="1.0583" r=".9388"/><circle cx="8.0083" cy="1.0583" r=".9388"/></g>
        </svg>
      '';
      "hypr-dock/themes/catppuccin/point/3.svg".text = ''
        <svg width="48" height="9" viewBox="0 0 12.7 2.3812" xmlns="http://www.w3.org/2000/svg">
          <g transform="translate(-1.6591)" fill="${accentHex}"><circle cx="4.6917" cy="1.0583" r=".9388"/><circle cx="8.0083" cy="1.0583" r=".9388"/><circle cx="11.327" cy="1.0614" r=".9388"/></g>
        </svg>
      '';
    };
  };
}
