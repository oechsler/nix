# Rofi Configuration (Hyprland Launcher)
#
# This module configures rofi as application launcher and provides several rofi-based menus:
# 1. Application launcher (drun mode)
# 2. Window switcher (window mode)
# 3. Power menu (lock, suspend, logout, reboot, shutdown)
# 4. Clipboard manager (with image preview support)
# 5. Power profile switcher (performance, balanced, power-saver)
# 6. Places menu (removable media, bookmarks, SMB shares)
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

{
  config,
  pkgs,
  lib,
  fonts,
  theme,
  i18n,
  features,
  ...
}:

let
  inherit (i18n) translate;
  powerPrompt = translate "Power" "Energie";
  powerLock = "󰌾  ${translate "Lock" "Sperren"}";
  powerSuspend = "󰒲  ${translate "Suspend" "Standby"}";
  powerLogout = "󰍃  ${translate "Log out" "Abmelden"}";
  powerReboot = "󰜉  ${translate "Reboot" "Neustart"}";
  powerOff = "󰐥  ${translate "Shut down" "Herunterfahren"}";
  powerFirmware = "󰘚  ${translate "Firmware" "Firmware"}";
  profileBalanced = "󰾆  ${translate "Balanced" "Ausgewogen"}";
  profileSaver = "󰌪  ${translate "Power saver" "Energiesparen"}";
  profilePerformance = "󱐋  ${translate "Performance" "Leistung"}";
  profilePrompt = translate "Power profile" "Energieprofil";
  placesPrompt = translate "Places" "Orte";

  places =
    config.fileManager.bookmarks
    ++ map (share: {
      name = share.label;
      path = "${config.home.homeDirectory}/smb/${share.label}";
      icon = "network-server";
    }) features.smb.shares;

  placesEntries = lib.concatMapStringsSep "\n" (place: ''
    printf '%s\0icon\x1f%s\n' ${lib.escapeShellArg place.name} ${lib.escapeShellArg place.icon}
  '') places;

  placesCases = lib.concatMapStringsSep "\n" (place: ''
    ${lib.escapeShellArg place.name}) open_path ${lib.escapeShellArg place.path} ;;
  '') places;

  openPath = ''${pkgs.xdg-utils}/bin/xdg-open "$1" >/dev/null 2>&1 &'';

  placesMenu = pkgs.writeShellScript "rofi-places" ''
    if pgrep -x rofi > /dev/null; then
      if pgrep -fa "rofi -dmenu.*${placesPrompt}" > /dev/null; then
        pkill -x rofi
        exit 0
      fi
      pkill -x rofi
    fi

    open_path() {
      ${openPath}
    }

    removable_mounts=$(${pkgs.util-linux}/bin/lsblk --json --output LABEL,MOUNTPOINT,RM,TYPE 2>/dev/null \
      | ${pkgs.jq}/bin/jq -r '.blockdevices[]? | recurse(.children[]?) | select(.rm == true and .mountpoint != null) | [(.label // "Wechselmedium"), .mountpoint] | @tsv')

    choice=$(
      {
        while IFS=$'\t' read -r label mountpoint; do
          if [ -n "$mountpoint" ]; then
            printf '%s\0icon\x1f%s\n' "$label" "drive-removable-media"
          fi
        done <<< "$removable_mounts"

        ${placesEntries}
      } | rofi -dmenu -p ${lib.escapeShellArg placesPrompt} -i -no-custom -show-icons \
          -theme-str 'element-icon { size: 22px; }'
    )

    case "$choice" in
      ${placesCases}
    esac

    while IFS=$'\t' read -r label mountpoint; do
      if [ "$label" = "$choice" ] && [ -n "$mountpoint" ]; then
        open_path "$mountpoint"
        exit 0
      fi
    done <<< "$removable_mounts"
  '';

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
  toggleRofi =
    mode:
    pkgs.writeShellScript "rofi-${mode}" ''
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
  # - 󰘚 UEFI (Firmware Setup) - Reboot into UEFI firmware settings
  powerMenu = pkgs.writeShellScript "rofi-power-menu" ''
    suspend() {
      ${import ./scripts/lock-suspend.nix { inherit pkgs; }}
    }

    if pgrep -x rofi > /dev/null && pgrep -fa "rofi -dmenu -p ${powerPrompt}" > /dev/null; then
      pkill -x rofi
      exit 0
    fi
    pgrep -x rofi > /dev/null && exit 0
    choice=$(printf '%s\n' "${powerLock}" "${powerSuspend}" "${powerLogout}" "${powerReboot}" "${powerOff}" "${powerFirmware}" | rofi -dmenu -p "${powerPrompt}" -i -no-custom -no-show-icons -lines 6)
    case "$choice" in
      "${powerLock}")     hyprlock ;;
      "${powerSuspend}")  suspend ;;
      "${powerLogout}")   ${pkgs.uwsm}/bin/uwsm stop ;;
      "${powerReboot}")   systemctl reboot ;;
      "${powerOff}")      systemctl poweroff ;;
      "${powerFirmware}") systemctl reboot --firmware-setup ;;
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
      content="''${line#*	}"
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
      elif [[ "$content" == file://* ]]; then
        path=$(${pkgs.python3}/bin/python3 -c 'import sys, urllib.parse; print(urllib.parse.unquote(urllib.parse.urlparse(sys.argv[1]).path))' "$content")
        mime=$(${pkgs.file}/bin/file --brief --mime-type -- "$path" 2>/dev/null || true)
        if [[ "$mime" == image/* ]]; then
          printf '%s\0icon\x1f%s\n' "$line" "$path"
        else
          printf '%s\0icon\x1ftext-x-generic\n' "$line"
        fi
      else
        printf '%s\0icon\x1ftext-x-generic\n' "$line"
      fi
    done | rofi -dmenu -p "Zwischenablage" -show-icons -theme-str 'element-icon { size: 22px; }' | cliphist decode | ${pkgs.wl-clipboard}/bin/wl-copy
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
    if pgrep -x rofi > /dev/null && pgrep -fa "rofi -dmenu -p" > /dev/null; then
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
        profiles="${profileBalanced}\n${profileSaver}\n${profilePerformance}"
        ;;
      "power-saver")
        profiles="${profileSaver}\n${profileBalanced}\n${profilePerformance}"
        ;;
      "performance")
        profiles="${profilePerformance}\n${profileBalanced}\n${profileSaver}"
        ;;
    esac

    choice=$(printf '%b' "$profiles" | rofi -dmenu -p "${profilePrompt}" -i -no-custom -no-show-icons)
    case "$choice" in
      "${profileBalanced}")   ${pkgs.power-profiles-daemon}/bin/powerprofilesctl set balanced ;;
      "${profileSaver}")      ${pkgs.power-profiles-daemon}/bin/powerprofilesctl set power-saver ;;
      "${profilePerformance}") ${pkgs.power-profiles-daemon}/bin/powerprofilesctl set performance ;;
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
    places = lib.mkOption {
      type = lib.types.path;
      default = placesMenu;
      readOnly = true;
      description = "Script to show file manager bookmarks and SMB shares";
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
        display-window = translate "Windows" "Fenster";
        window-format = "{w}  {c}  {t}";
        window-match-fields = "title,class,role,name";
        kb-row-up = "Up,Alt+k";
        kb-row-down = "Down,Alt+j";
      };
      theme =
        let
          inherit (config.lib.formats.rasi) mkLiteral;
          palette = config.theme.catppuccinPalette;
          stripHash = hex: lib.removePrefix "#" hex;
          accentColor = "@${config.catppuccin.accent}";
          # Rasi does not support GTK's alpha() color function. Keep the
          # Catppuccin glass color in its native Rasi-compatible form.
          glassColor = mkLiteral "#${stripHash palette.base.hex}eb";
        in
        {
          "window" = {
            width = mkLiteral "680px";
            border = mkLiteral "${toString theme.border.width}px solid";
            border-color = mkLiteral accentColor;
            border-radius = mkLiteral "${toString theme.radius.default}px";
            background-color = glassColor;
          };
          "mainbox" = {
            padding = mkLiteral "${toString theme.spacing.panel}px";
            background-color = mkLiteral "transparent";
            spacing = mkLiteral "0px";
          };
          "inputbar" = {
            height = mkLiteral "56px";
            children = map mkLiteral [
              "prompt"
              "entry"
            ];
            background-color = mkLiteral "transparent";
            border = mkLiteral "${toString theme.border.width}px solid";
            border-color = mkLiteral "@surface1";
            border-radius = mkLiteral "${toString theme.radius.default}px";
            padding = mkLiteral "${toString theme.spacing.control}px ${toString theme.spacing.panel}px";
            spacing = mkLiteral "${toString theme.spacing.control}px";
          };
          "prompt" = {
            text-color = mkLiteral accentColor;
            font = "${fonts.ui} Bold ${toString fonts.size}";
            background-color = mkLiteral "transparent";
          };
          "entry" = {
            placeholder = "Suchen...";
            placeholder-color = mkLiteral "@overlay1";
            text-color = mkLiteral "@subtext1";
            font = "${fonts.ui} Medium ${toString fonts.size}";
            background-color = mkLiteral "transparent";
          };
          "listview" = {
            lines = 6;
            fixed-height = false;
            dynamic = true;
            padding = mkLiteral "${toString theme.spacing.content}px 0px 0px 0px";
            spacing = mkLiteral "0px";
            border = mkLiteral "0px";
            scrollbar = false;
            background-color = mkLiteral "transparent";
          };
          "element" = {
            padding = mkLiteral "${toString theme.spacing.control}px ${toString theme.spacing.panel}px";
            spacing = mkLiteral "${toString theme.spacing.content}px";
            background-color = mkLiteral "transparent";
            text-color = mkLiteral "@subtext0";
            border-radius = mkLiteral "${toString theme.radius.default}px";
          };
          "element normal.normal" = {
            background-color = mkLiteral "transparent";
            text-color = mkLiteral "@subtext0";
          };
          "element alternate.normal" = {
            background-color = mkLiteral "transparent";
            text-color = mkLiteral "@subtext0";
          };
          "element normal.active" = {
            background-color = mkLiteral "transparent";
            text-color = mkLiteral "@subtext0";
          };
          "element alternate.active" = {
            background-color = mkLiteral "transparent";
            text-color = mkLiteral "@subtext0";
          };
          "element selected.normal" = {
            background-color = mkLiteral accentColor;
            text-color = mkLiteral "@base";
            border-radius = mkLiteral "${toString theme.radius.default}px";
          };
          "element selected.active" = {
            background-color = mkLiteral accentColor;
            text-color = mkLiteral "@base";
            border-radius = mkLiteral "${toString theme.radius.default}px";
          };
          "element selected.urgent" = {
            background-color = mkLiteral "@red";
            text-color = mkLiteral "@crust";
            border-radius = mkLiteral "${toString theme.radius.default}px";
          };
          "element-icon" = {
            size = mkLiteral "22px";
            text-color = mkLiteral "inherit";
            background-color = mkLiteral "transparent";
          };
          "element-text" = {
            font = "${fonts.ui} Medium ${toString fonts.size}";
            text-color = mkLiteral "inherit";
            background-color = mkLiteral "transparent";
          };
        };
    };

    # Hide Rofi from drun
    home.file = {
      ".local/share/applications/rofi.desktop".text = ''
        [Desktop Entry]
        Type=Application
        Name=Rofi
        Exec=rofi
        Hidden=true
      '';
      ".local/share/applications/rofi-theme-selector.desktop".text = ''
        [Desktop Entry]
        Type=Application
        Name=Rofi Theme Selector
        Exec=rofi-theme-selector
        Hidden=true
      '';
      ".local/share/applications/gvim.desktop".text = ''
        [Desktop Entry]
        Type=Application
        Name=GVim
        Exec=gvim
        Hidden=true
      '';
      ".local/share/applications/uurecord.desktop".text = ''
        [Desktop Entry]
        Type=Application
        Name=uurecord
        Exec=uurecord
        Hidden=true
      '';
      ".local/share/applications/uuctl.desktop".text = ''
        [Desktop Entry]
        Type=Application
        Name=uuctl
        Exec=uuctl
        Hidden=true
      '';
      ".local/share/applications/qt5ct.desktop".text = ''
        [Desktop Entry]
        Type=Application
        Name=Qt5 Settings
        Exec=qt5ct
        Hidden=true
      '';
      ".local/share/applications/qt6ct.desktop".text = ''
        [Desktop Entry]
        Type=Application
        Name=Qt6 Settings
        Exec=qt6ct
        Hidden=true
      '';
    };
    home.file.".local/share/applications/kvantummanager.desktop".text = ''
      [Desktop Entry]
      Type=Application
      Name=Kvantum Manager
      Exec=kvantummanager
      Hidden=true
    '';
  };
}
