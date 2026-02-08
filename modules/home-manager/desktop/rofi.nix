{ config, pkgs, lib, theme, ... }:

let
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

  toggleDrun = toggleRofi "drun";
  toggleWindow = toggleRofi "window";

  powerMenu = pkgs.writeShellScript "rofi-power-menu" ''
    if pgrep -x rofi > /dev/null && pgrep -fa "rofi -dmenu -p power" > /dev/null; then
      pkill -x rofi
      exit 0
    fi
    pgrep -x rofi > /dev/null && exit 0
    choice=$(printf "󰌾  Sperren\n󰒲  Standby\n󰍃  Abmelden\n󰜉  Neustart\n󰐥  Herunterfahren" | rofi -dmenu -p "Energie" -i -no-custom)
    case "$choice" in
      "󰌾  Sperren")        hyprlock ;;
      "󰒲  Standby")       systemctl suspend ;;
      "󰍃  Abmelden")      hyprctl dispatch exit ;;
      "󰜉  Neustart")       systemctl reboot ;;
      "󰐥  Herunterfahren") systemctl poweroff ;;
    esac
  '';

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

  config = {
    # Let catppuccin module handle colors
    catppuccin.rofi.enable = true;

    programs.rofi = {
      enable = true;
      extraConfig = {
        show-icons = true;
        icon-theme = theme.icons.name;
        drun-match-fields = "name,exec";
        drun-display-format = "{name}";
        disable-history = false;
        sorting-method = "fzf";
        sort = true;
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
