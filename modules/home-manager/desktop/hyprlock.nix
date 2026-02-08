{ config, pkgs, lib, theme, fonts, displays, ... }:

{
  catppuccin.hyprlock.useDefaultConfig = false;

  programs.hyprlock = {
    enable = true;

    settings = {
      general = {
        hide_cursor = true;
        grace = 3;
      };

      background =
        if displays.monitors == [] then
          [{ path = "${theme.wallpaper}"; blur_passes = 3; blur_size = 8; }]
        else
          map (m: {
            monitor = m.name;
            path = "${if m.wallpaper != null then m.wallpaper else theme.wallpaper}";
            blur_passes = 3;
            blur_size = 8;
          }) displays.monitors;

      input-field = [
        {
          size = "320, 55";
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

      label = [
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
