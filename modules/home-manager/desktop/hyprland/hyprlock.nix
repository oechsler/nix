# Hyprlock Configuration (Screen Locker)
#
# This module configures hyprlock as the screen locker for Hyprland.
#
# Features:
# - Blurred wallpaper background (per-monitor support)
# - Time and date display
# - Password input field with Catppuccin colors
# - Grace period (3 seconds before lock activates)
# - Failed login attempt counter
# - Caps lock indicator
#
# UI Elements:
# - Background: Wallpaper with blur (3 passes, size 8)
# - Time: Large bold clock (120pt) in center
# - Date: Smaller date below clock (22pt)
# - Input field: Password entry (bottom center, 10% from bottom)
#
# Colors (Catppuccin):
# - Base: Input field background
# - Accent: Input field border (normal)
# - Red: Failed login border
# - Peach: Caps lock border
# - Text: Text color

{ theme, fonts, displays, ... }:

{
  #===========================
  # Configuration
  #===========================

  # Don't use default catppuccin config (we customize it)
  catppuccin.hyprlock.useDefaultConfig = false;

  programs.hyprlock = {
    enable = true;

    settings = {

      #---------------------------
      # General Settings
      #---------------------------
      general = {
        hide_cursor = true;  # Hide mouse cursor on lock screen
        grace = 3;           # Grace period (seconds) before locking
      };

      #---------------------------
      # Background
      #---------------------------
      # Wallpaper with blur effect (per-monitor)
      background =
        if displays.monitors == [] then
          # Fallback for no monitor config
          [{ path = "${theme.wallpaperPath}"; blur_passes = 3; blur_size = 8; }]
        else
          # Per-monitor wallpaper support
          map (m: {
            monitor = m.name;
            path = "${if m.wallpaper != null then m.wallpaper else theme.wallpaperPath}";
            blur_passes = 3;  # Number of blur passes (more = stronger blur)
            blur_size = 8;    # Blur radius
          }) displays.monitors;

      #---------------------------
      # Input Field
      #---------------------------
      # Password entry field
      input-field = [
        {
          size = "250, 42";
          position = "0, 10%";
          halign = "center";
          valign = "bottom";
          outline_thickness = theme.border.width;
          rounding = -1;
          dots_size = 0.25;
          dots_spacing = 0.2;
          dots_center = true;
          fade_on_empty = true;
          fade_timeout = 1000;
          inner_color = "$base";
          outer_color = "$accent";
          font_color = "$text";
          check_color = "$accent";
          fail_color = "$red";
          capslock_color = "$peach";
          placeholder_text = "Passwort";
          fail_text = "$FAIL ($ATTEMPTS)";
          font_family = "${fonts.ui}";
        }
      ];

      #---------------------------
      # Labels
      #---------------------------
      # Time and date display
      label = [
        # Time (large, center)
        {
          text = "$TIME";
          color = "$text";
          font_size = 120;
          font_family = "${fonts.ui}";
          font_style = "Bold";
          position = "0, 40";
          halign = "center";
          valign = "center";
        }
        {
          text = "cmd[update:60000] date +'%A, %-d. %B'";
          color = "$subtext0";
          font_size = 22;
          font_family = "${fonts.ui}";
          position = "0, -80";
          halign = "center";
          valign = "center";
        }
      ];
    };
  };
}
