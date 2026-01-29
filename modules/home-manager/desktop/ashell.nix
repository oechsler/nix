{ config, pkgs, ... }:

{
  programs.ashell = {
    enable = true;
    systemd.enable = true;

    settings = {
      position = "Top";
      app_launcher_cmd = "rofi -show drun";

      modules = {
        left = [ "AppLauncher" "Workspaces" "WindowTitle" ];
        right = [ "Tray" "Settings" "Clock" ];
      };

      workspaces = {
        enable_workspace_filling = true;
        max_workspaces = 4;
      };

      window_title = {
        mode = "Title";
        truncate_title_after_length = 50;
      };

      clock.format = "%H:%M";

      appearance = {
        scale_factor = 1.25;
        font_name = "JetBrainsMono Nerd Font";

        # Catppuccin Mocha Lavender Theme
        background_color = "#1e1e2e";
        primary_color = "#b4befe";
        secondary_color = "#45475a";
        success_color = "#a6e3a1";
        danger_color = "#f38ba8";
        text_color = "#cdd6f4";

        workspace_colors = [ "#b4befe" "#cba6f7" "#89b4fa" "#94e2d5" ];
      };
    };
  };
}
