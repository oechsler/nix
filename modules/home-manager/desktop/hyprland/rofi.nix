# Rofi Configuration (Hyprland Launcher)
#
# This module configures rofi as application launcher and provides several rofi-based menus:
# 1. Application launcher (drun mode)
# 2. Window switcher (window mode)
# 3. Power menu (lock, suspend, logout, reboot, shutdown)
# 4. Clipboard manager (with image preview support)
# 5. Power profile switcher (performance, balanced, power-saver)
#
# Features:
# - Toggle behavior: Press same key again to close
# - Smart mode switching: Automatically closes old mode when opening new one
# - Catppuccin theme integration
# - Icon support
# - Image previews in clipboard history
#
# Scripts exposed as config.rofi.*:
#   config.rofi.toggle          - Application launcher
#   config.rofi.windowList      - Window switcher
#   config.rofi.power           - Power menu
#   config.rofi.clipboard       - Clipboard manager
#   config.rofi.powerProfile    - Power profile menu

{ config, pkgs, lib, fonts, theme, ... }:

let
  # ============================================================================
  # TOGGLE ROFI SCRIPT
  # ============================================================================
  # Generic rofi toggle script with mode support
  #
  # Behavior:
  # - If rofi is running with same mode: Close it
  # - If rofi is running with different mode: Switch to new mode
  # - If rofi is not running: Open with specified mode
  #
  # Args:
  #   mode = rofi mode (e.g., "drun", "window")
  toggleRofi = mode: pkgs.writeShellScript "rofi-${mode}" ''
    if pgrep -x "rofi" > /dev/null; then
      # Check if rofi is running with the same mode
      if pgrep -fa "rofi.*-show ${mode}" > /dev/null; then
        pkill -x rofi
      else
        # Different mode requested - restart with new mode
        pkill -x rofi
        rofi -show ${mode}
      fi
    else
      rofi -show ${mode}
    fi
  '';

  # Application launcher (drun = desktop run)
  toggleDrun = toggleRofi "drun";

  # Window switcher
  toggleWindow = toggleRofi "window";

  # ============================================================================
  # POWER MENU SCRIPT
  # ============================================================================
  # Rofi-based power menu with icons
  #
  # Options:
  # - 󰌾 Sperren (Lock) - Lock screen with hyprlock
  # - 󰒲 Standby (Suspend) - Lock then suspend
  # - 󰍃 Abmelden (Logout) - Exit Hyprland
  # - 󰜉 Neustart (Reboot) - Reboot system
  # - 󰐥 Herunterfahren (Shutdown) - Power off system
  powerMenu = pkgs.writeShellScript "rofi-power-menu" ''
    if pgrep -x rofi > /dev/null && pgrep -fa "rofi -dmenu -p power" > /dev/null; then
      pkill -x rofi
      exit 0
    fi
    pgrep -x rofi > /dev/null && exit 0
    choice=$(printf "󰌾  Sperren\n󰒲  Standby\n󰍃  Abmelden\n󰜉  Neustart\n󰐥  Herunterfahren" | rofi -dmenu -p "Energie" -i -no-custom)
    case "$choice" in
      "󰌾  Sperren")        hyprlock ;;
      "󰒲  Standby")       loginctl lock-session && sleep 2 && systemctl suspend ;;
      "󰍃  Abmelden")      hyprctl dispatch exit ;;
      "󰜉  Neustart")       systemctl reboot ;;
      "󰐥  Herunterfahren") systemctl poweroff ;;
    esac
  '';

  # ============================================================================
  # CLIPBOARD HISTORY SCRIPT
  # ============================================================================
  # Rofi-based clipboard manager with image preview support
  #
  # Features:
  # - Shows clipboard history from cliphist
  # - Image previews for copied images (PNG thumbnails in /tmp/cliphist-previews/)
  # - Text entries shown as-is
  # - Select entry to copy to clipboard
  #
  # How it works:
  # 1. List clipboard history with cliphist
  # 2. For images: Generate PNG preview and show as icon
  # 3. For text: Show text directly
  # 4. User selects entry → decode and copy to clipboard
  cliphistRofi = pkgs.writeShellScript "rofi-clipboard" ''
    if pgrep -x "rofi" > /dev/null; then
      if pgrep -fa "rofi.*-dmenu.*clipboard" > /dev/null; then
        pkill -x rofi
        exit 0
      else
        pkill -x rofi
      fi
    fi

    preview_dir="/tmp/cliphist-previews"
    mkdir -p "$preview_dir"

    cliphist list | while IFS= read -r line; do
      id="''${line%%	*}"
      if printf '%s' "$line" | ${pkgs.gnugrep}/bin/grep -q '\[\[.*binary.*image'; then
        cache="$preview_dir/$id.png"
        if [ ! -s "$cache" ]; then
          printf '%s' "$line" | cliphist decode > "$cache" 2>/dev/null
        fi
        if [ -s "$cache" ]; then
          printf '%s\0icon\x1f%s\n' "$line" "$cache"
        else
          printf '%s\n' "$line"
        fi
      else
        printf '%s\n' "$line"
      fi
    done | rofi -dmenu -p "Zwischenablage" -show-icons | cliphist decode | ${pkgs.wl-clipboard}/bin/wl-copy
  '';

  # ============================================================================
  # POWER PROFILE MENU SCRIPT
  # ============================================================================
  # Rofi-based power profile switcher
  #
  # Profiles:
  # - Performance - Maximum performance, higher power consumption
  # - Balanced - Balance between performance and power saving
  # - Power Saver - Maximum battery life, reduced performance
  #
  # Shows current profile first in the list
  powerProfileMenu = pkgs.writeShellScript "rofi-power-profile" ''
    if pgrep -x rofi > /dev/null && pgrep -fa "rofi -dmenu -p.*[Pp]ower.*[Pp]rofil" > /dev/null; then
      pkill -x rofi
      exit 0
    fi
    pgrep -x rofi > /dev/null && exit 0

    # Get current profile
    current=$(${pkgs.power-profiles-daemon}/bin/powerprofilesctl get)

    # Build menu with current profile first
    profiles=""
    case "$current" in
      "balanced")
        profiles="󰾆  Ausgewogen\n󰌪  Energiesparen\n󱐋  Leistung"
        ;;
      "power-saver")
        profiles="󰌪  Energiesparen\n󰾆  Ausgewogen\n󱐋  Leistung"
        ;;
      "performance")
        profiles="󱐋  Leistung\n󰾆  Ausgewogen\n󰌪  Energiesparen"
        ;;
    esac

    choice=$(printf "$profiles" | rofi -dmenu -p "Energieprofil" -i -no-custom)
    case "$choice" in
      "󰾆  Ausgewogen")     ${pkgs.power-profiles-daemon}/bin/powerprofilesctl set balanced ;;
      "󰌪  Energiesparen")  ${pkgs.power-profiles-daemon}/bin/powerprofilesctl set power-saver ;;
      "󱐋  Leistung")       ${pkgs.power-profiles-daemon}/bin/powerprofilesctl set performance ;;
    esac
  '';
in
{
  #===========================
  # Options
  #===========================
  # Expose rofi scripts as options for use in keybindings

  options.rofi = {
    toggle = lib.mkOption {
      type = lib.types.path;
      default = toggleDrun;
      readOnly = true;
      description = "Script to toggle rofi drun";
    };
    windowList = lib.mkOption {
      type = lib.types.path;
      default = toggleWindow;
      readOnly = true;
      description = "Script to toggle rofi window list";
    };
    clipboard = lib.mkOption {
      type = lib.types.path;
      default = cliphistRofi;
      readOnly = true;
      description = "Script to show clipboard history in rofi";
    };
    power = lib.mkOption {
      type = lib.types.path;
      default = powerMenu;
      readOnly = true;
      description = "Script to show power menu in rofi";
    };
    powerProfile = lib.mkOption {
      type = lib.types.path;
      default = powerProfileMenu;
      readOnly = true;
      description = "Script to show power profile selector in rofi";
    };
  };

  #===========================
  # Configuration
  #===========================

  config = {
    # Catppuccin theme integration
    catppuccin.rofi.enable = true;

    programs.rofi = {
      enable = true;
      font = "${fonts.ui} ${toString fonts.size}";
      extraConfig = {
        show-icons = true;
        icon-theme = theme.icons.name;
        drun-match-fields = "name,exec";
        drun-display-format = "{name}";
        disable-history = false;
        sorting-method = "fzf";
        display-drun = "Apps";
        display-window = "Fenster";
      };
      theme = let
        inherit (config.lib.formats.rasi) mkLiteral;
        accentColor = "@${config.catppuccin.accent}";
      in {
        "window" = {
          width = mkLiteral "33%";
          border = mkLiteral "${toString theme.border.width}px solid";
          border-color = mkLiteral accentColor;
          border-radius = mkLiteral "${toString theme.radius.default}px";
        };
        "element" = {
          border-radius = mkLiteral "${toString theme.radius.small}px";
        };
        "element selected.normal" = {
          background-color = mkLiteral accentColor;
          text-color = mkLiteral "@base";
        };
        "element selected.active" = {
          background-color = mkLiteral accentColor;
          text-color = mkLiteral "@base";
        };
        "element selected.urgent" = {
          background-color = mkLiteral "@red";
          text-color = mkLiteral "@base";
        };
        "inputbar" = {
          border-radius = mkLiteral "${toString theme.radius.small}px";
        };
      };
    };

    # Hide Rofi from drun
    home.file.".local/share/applications/rofi.desktop".text = ''
      [Desktop Entry]
      Type=Application
      Name=Rofi
      Exec=rofi
      Hidden=true
    '';
    home.file.".local/share/applications/rofi-theme-selector.desktop".text = ''
      [Desktop Entry]
      Type=Application
      Name=Rofi Theme Selector
      Exec=rofi-theme-selector
      Hidden=true
    '';
    home.file.".local/share/applications/gvim.desktop".text = ''
      [Desktop Entry]
      Type=Application
      Name=GVim
      Exec=gvim
      Hidden=true
    '';
    home.file.".local/share/applications/uurecord.desktop".text = ''
      [Desktop Entry]
      Type=Application
      Name=uurecord
      Exec=uurecord
      Hidden=true
    '';
    home.file.".local/share/applications/uuctl.desktop".text = ''
      [Desktop Entry]
      Type=Application
      Name=uuctl
      Exec=uuctl
      Hidden=true
    '';
    home.file.".local/share/applications/qt5ct.desktop".text = ''
      [Desktop Entry]
      Type=Application
      Name=Qt5 Settings
      Exec=qt5ct
      Hidden=true
    '';
    home.file.".local/share/applications/qt6ct.desktop".text = ''
      [Desktop Entry]
      Type=Application
      Name=Qt6 Settings
      Exec=qt6ct
      Hidden=true
    '';
    home.file.".local/share/applications/kvantummanager.desktop".text = ''
      [Desktop Entry]
      Type=Application
      Name=Kvantum Manager
      Exec=kvantummanager
      Hidden=true
    '';
  };
}
