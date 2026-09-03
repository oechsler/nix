# Hypr Dock Configuration (Hyprland Application Dock)
#
# This module configures hypr-dock as the application dock for Hyprland.
#
# Features:
# - Pinned applications (from features.desktop.pinnedApps)
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

{
  config,
  pkgs,
  lib,
  theme,
  features,
  ...
}:

let
  # Catppuccin palette (shared via common/theme.nix)
  palette = config.theme.catppuccinPalette;
  accentHex = palette.${config.catppuccin.accent}.hex;
  baseHex = palette.base.hex;
  surfaceHex = palette.surface0.hex;
  textHex = palette.text.hex;
  themeTrigger = pkgs.writeText "hypr-dock-theme-trigger" (
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
  configTrigger = pkgs.writeText "hypr-dock-config-trigger" (
    builtins.toJSON {
      pinnedApps = features.desktop.pinnedApps.entries;
      iconSize = 36;
      position = "bottom";
      previewMode = "live";
    }
  );
  startScript = pkgs.writeShellScript "hypr-dock-start" ''
    set -eu
    ${pkgs.coreutils}/bin/sleep 3
    exec ${pkgs.hypr-dock}/bin/hypr-dock
  '';
in
{
  #===========================
  # Configuration
  #===========================

  config = lib.mkIf (features.desktop.enable && features.desktop.wm == "hyprland") {

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
        After = [ "graphical-session.target" ];
        PartOf = [ "graphical-session.target" ];
        ConditionEnvironment = "WAYLAND_DISPLAY";
        X-Restart-Triggers = [
          config.theme.catppuccin.restartTrigger
          themeTrigger
          configTrigger
        ];
      };
      Service = {
        # Let Hyprland finish applying its config before the dock reads gaps
        # and creates its layer-shell surface.
        ExecStart = startScript;
        Restart = "on-failure";
        RestartSec = 2;
        # Only kill the dock process, not apps launched from it
        KillMode = "process";
        # Electron apps launched from the dock inherit this env var.
        # nixpkgs wrappers then automatically add --ozone-platform=wayland.
        Environment = "NIXOS_OZONE_WL=1";
      };
      Install.WantedBy = [ "graphical-session.target" ];
    };

    #---------------------------
    # 3. Dock Configuration
    #---------------------------
    # Main dock settings (position, size, margins)
    # Format changed in v1.2.1: config.jsonc (JSON) → hypr-dock.conf (INI)
    # Layer "exclusive-bottom" split into Layer + Exclusive options
    xdg.configFile = {
      "hypr-dock/hypr-dock.conf".text = ''
        [General]
        CurrentTheme = catppuccin
        IconSize = 36
        Layer = bottom
        Exclusive = true
        SmartView = false
        Position = bottom
        AutoHideDelay = 400
        SystemGapUsed = true
        Margin = ${toString theme.gaps.outer}
        ContextPos = 5

        [General.preview]
        Mode = live
        FPS = 30
        BufferSize = 5
        ShowDelay = 500
        HideDelay = 350
        MoveDelay = 100
      '';

      #---------------------------
      # 5. Catppuccin Theme
      #---------------------------
      # Theme configuration (generated from Catppuccin palette)
      # Format changed in v1.2.1: catppuccin.jsonc (JSON) → theme.conf (INI)
      "hypr-dock/themes/catppuccin/theme.conf".text = ''
        [Theme]
        Blur = true
        Spacing = ${toString theme.spacing.compact}

        [Theme.preview]
        Size = 120
        BorderRadius = ${toString theme.radius.small}
        Padding = ${toString theme.spacing.control}
      '';
      "hypr-dock/themes/catppuccin/style.css".text = ''
        window {
          background-color: transparent;
        }

        #app {
           background-color: alpha(${baseHex}, ${lib.strings.floatToString theme.alpha.container});
          border-radius: ${toString theme.radius.default}px;
           border: ${toString theme.border.width}px solid ${accentHex};
           padding: ${toString theme.spacing.compact}px;
        }

        button {
          background-color: rgba(0, 0, 0, 0);
           padding: ${toString theme.spacing.compact}px;
           margin: ${toString (theme.spacing.compact / 4)}px;
          border-radius: ${toString theme.radius.default}px;
          border: none;
          transition: all 120ms cubic-bezier(0.23, 1, 0.32, 1);
        }

        button:hover {
           background-color: alpha(${accentHex}, ${lib.strings.floatToString theme.alpha.hover});
        }

        button:active {
           background-color: alpha(${accentHex}, ${lib.strings.floatToString theme.alpha.active});
        }

        #menu-item {
          padding: 3px;
          padding-left: 0;
        }

        menu {
           background-color: alpha(${baseHex}, ${lib.strings.floatToString theme.alpha.container});
           border: ${toString theme.border.width}px solid alpha(${accentHex}, ${lib.strings.floatToString theme.alpha.border});
          border-radius: ${toString theme.radius.small}px;
          box-shadow: 0 4px 12px rgba(0, 0, 0, 0.3);
          outline: none;
          background-image: none;
           padding: ${toString theme.spacing.compact}px;
        }

        menuitem {
          color: ${textHex};
           padding: ${toString theme.spacing.compact}px ${toString theme.spacing.control}px;
          border-radius: ${toString theme.radius.small}px;
          transition: all 0.18s cubic-bezier(0.23, 1, 0.32, 1);
        }

        menuitem:hover {
          background-color: alpha(${accentHex}, 0.2);
          color: ${accentHex};
        }

        #pv-item {
           background-color: alpha(${surfaceHex}, ${lib.strings.floatToString theme.alpha.surface});
          transition: all 0.18s cubic-bezier(0.23, 1, 0.32, 1);
          border-radius: ${toString theme.radius.small}px;
           border: ${toString theme.border.subtle}px solid alpha(${accentHex}, ${lib.strings.floatToString theme.alpha.subtle});
        }

        #pv-item.hover {
           background-color: alpha(${accentHex}, ${lib.strings.floatToString theme.alpha.hover});
           border-color: alpha(${accentHex}, ${lib.strings.floatToString theme.alpha.border});
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

    #---------------------------
    # 4. Pinned Applications
    #---------------------------
    # v1.2.1: pins moved to ~/.local/share/hypr-dock/pinned (plain text, one per line)
    # Use activation script (not xdg.dataFile) so the dock can write to the file
    # while we manage the canonical list. Config is source of truth — written on
    # every switch so additions and removals take effect immediately.
    home.activation.hyprDockPins = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      _pinned_file="${config.xdg.dataHome}/hypr-dock/pinned"
      mkdir -p "$(dirname "$_pinned_file")"
       printf '%s\n' ${lib.escapeShellArgs features.desktop.pinnedApps.entries} > "$_pinned_file"
      systemctl --user try-restart hypr-dock.service >/dev/null 2>&1 || true
    '';
  };
}
