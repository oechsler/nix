{ config, pkgs, lib, ... }:

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
  };

  config = {
    # Let catppuccin module handle colors
    catppuccin.rofi.enable = true;

    programs.rofi = {
      enable = true;
      extraConfig = {
        show-icons = true;
        icon-theme = "Papirus-Dark";
        drun-match-fields = "name,exec";
        drun-display-format = "{name}";
        disable-history = false;
      };
      theme = let
        inherit (config.lib.formats.rasi) mkLiteral;
        accentColor = "@${config.catppuccin.accent}";
      in {
        "window" = {
          border = mkLiteral "2px solid";
          border-color = mkLiteral accentColor;
          border-radius = mkLiteral "16px";
        };
        "element" = {
          border-radius = mkLiteral "4px";
        };
        "inputbar" = {
          border-radius = mkLiteral "4px";
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
  };
}
