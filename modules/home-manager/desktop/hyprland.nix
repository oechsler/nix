{ config, pkgs, inputs, theme, fonts, ... }:

let
  # Volume-Notification mit Progress Bar (Nerd Font Icons)
  volumeNotify = pkgs.writeShellScript "volume-notify" ''
    volume=$(${pkgs.wireplumber}/bin/wpctl get-volume @DEFAULT_AUDIO_SINK@ | ${pkgs.gawk}/bin/awk '{printf "%.0f", $2 * 100}')
    muted=$(${pkgs.wireplumber}/bin/wpctl get-volume @DEFAULT_AUDIO_SINK@ | ${pkgs.gnugrep}/bin/grep -c MUTED)

    if [ "$muted" -eq 1 ]; then
      icon="󰝟"
      text="$icon  Stummgeschaltet"
      volume=0
    elif [ "$volume" -ge 70 ]; then
      icon="󰕾"
      text="$icon  Lautstärke ''${volume}%"
    elif [ "$volume" -ge 30 ]; then
      icon="󰖀"
      text="$icon  Lautstärke ''${volume}%"
    else
      icon="󰕿"
      text="$icon  Lautstärke ''${volume}%"
    fi

    ${pkgs.dunst}/bin/dunstify -a "changeVolume" -u low \
      -h string:x-dunst-stack-tag:volume \
      -h int:value:"$volume" \
      "$text"
  '';

  # Brightness-Notification mit Progress Bar (Nerd Font Icons)
  brightnessNotify = pkgs.writeShellScript "brightness-notify" ''
    brightness=$(${pkgs.brightnessctl}/bin/brightnessctl -m | ${pkgs.gawk}/bin/awk -F, '{print substr($4, 0, length($4)-1)}')

    if [ "$brightness" -ge 70 ]; then
      icon="󰃠"
    elif [ "$brightness" -ge 30 ]; then
      icon="󰃟"
    else
      icon="󰃞"
    fi

    ${pkgs.dunst}/bin/dunstify -a "changeBrightness" -u low \
      -h string:x-dunst-stack-tag:brightness \
      -h int:value:"$brightness" \
      "$icon  Helligkeit ''${brightness}%"
  '';
in
{
  imports = [
    ./waybar.nix
    ./rofi.nix
    ./awww.nix
    ./nautilus.nix
    ./hyprlock.nix
    ./hypridle.nix
    ./dunst.nix
  ];

  # Packages
  home.packages = [
    pkgs.brightnessctl
    pkgs.playerctl
    pkgs.hyprshot
    pkgs.wl-clipboard
    pkgs.cliphist
  ];

  wayland.windowManager.hyprland = {
    enable = true;
    xwayland.enable = true;

    systemd.enable = true;

    settings = {
      # Monitor
      monitor = ",preferred,auto,1.6";

      exec-once = [
        "uwsm-app -- ${config.awww.start}"
        "wl-paste --type text --watch cliphist store"
        "wl-paste --type image --watch cliphist store"
      ];

      # Environment variables
      env = [
        "XCURSOR_THEME,${theme.cursor.name}"
        "XCURSOR_SIZE,${toString theme.cursor.size}"
        "HYPRCURSOR_THEME,${theme.cursor.name}"
        "HYPRCURSOR_SIZE,${toString theme.cursor.size}"
        # Qt Theme - MUSS qt6ct sein, nicht kvantum!
        "QT_QPA_PLATFORMTHEME,qt6ct"
        # QT_STYLE_OVERRIDE NICHT setzen - das macht qt6ct
      ];

      # Cursor
      cursor = {
        no_hardware_cursors = true;
      };

      # Input - Deutsches Tastaturlayout
      input = {
        kb_layout = "de";
        kb_variant = "";
        kb_model = "";
        kb_options = "";
        kb_rules = "";

        follow_mouse = 1;
        sensitivity = 0;

        touchpad = {
          natural_scroll = false;
        };
      };

      # Gestures
      gesture = "3, horizontal, workspace";

      # General
      general = {
        gaps_in = 8;
        gaps_out = 16;
        border_size = 2;
        "col.active_border" = "$accent";
        "col.inactive_border" = "$surface0";
        resize_on_border = false;
        allow_tearing = false;
        layout = "dwindle";
      };

      # Decoration
      decoration = {
        rounding = 16;
        active_opacity = 1.0;
        inactive_opacity = 1.0;

        shadow = {
          enabled = true;
          range = 4;
          render_power = 3;
          color = "rgba(1a1a1aee)";
        };

        blur = {
          enabled = true;
          size = 3;
          passes = 1;
          vibrancy = 0.1696;
        };
      };

      # Animations
      animations = {
        enabled = true;

        bezier = [
          "easeOutQuint, 0.23, 1, 0.32, 1"
          "easeInOutCubic, 0.65, 0.05, 0.36, 1"
          "linear, 0, 0, 1, 1"
          "almostLinear, 0.5, 0.5, 0.75, 1"
          "quick, 0.15, 0, 0.1, 1"
        ];

        animation = [
          "global, 1, 10, default"
          "border, 1, 5.39, easeOutQuint"
          "windows, 1, 4.79, easeOutQuint"
          "windowsIn, 1, 4.1, easeOutQuint, popin 87%"
          "windowsOut, 1, 1.49, linear, popin 87%"
          "fadeIn, 1, 1.73, almostLinear"
          "fadeOut, 1, 1.46, almostLinear"
          "fade, 1, 3.03, quick"
          "layers, 1, 3.81, easeOutQuint"
          "layersIn, 1, 4, easeOutQuint, fade"
          "layersOut, 1, 1.5, linear, fade"
          "fadeLayersIn, 1, 1.79, almostLinear"
          "fadeLayersOut, 1, 1.39, almostLinear"
          "workspaces, 1, 1.94, almostLinear, fade"
          "workspacesIn, 1, 1.21, almostLinear, fade"
          "workspacesOut, 1, 1.94, almostLinear, fade"
        ];
      };

      # Layouts
      dwindle = {
        pseudotile = true;
        preserve_split = true;
      };

      master = {
        new_status = "master";
      };

      # Misc
      misc = {
        force_default_wallpaper = 0;
        disable_hyprland_logo = true;
      };

      # Keybindings
      "$mainMod" = "SUPER";

      bind = [
        # Main binds
        "$mainMod, Return, exec, kitty"
        "$mainMod, Q, killactive,"
        "$mainMod, M, exit,"
        "$mainMod SHIFT, Q, exec, hyprlock"
        "$mainMod, E, exec, nautilus"
        "$mainMod, V, togglefloating,"
        "$mainMod, R, exec, ${config.rofi.toggle}"
        "$mainMod, W, exec, ${config.rofi.windowList}"
        "$mainMod, P, pseudo,"
        "$mainMod, T, togglesplit,"

        # Screenshots
        ", Print, exec, hyprshot -m output"
        "$mainMod, Print, exec, hyprshot -m region"
        "$mainMod SHIFT, Print, exec, hyprshot -m window"

        # Clipboard
        "$mainMod, C, exec, ${config.rofi.clipboard}"

        # Move focus (vim + arrow keys)
        "$mainMod, H, movefocus, l"
        "$mainMod, L, movefocus, r"
        "$mainMod, K, movefocus, u"
        "$mainMod, J, movefocus, d"
        "$mainMod, left, movefocus, l"
        "$mainMod, right, movefocus, r"
        "$mainMod, up, movefocus, u"
        "$mainMod, down, movefocus, d"

        # Move windows (vim + arrow keys)
        "$mainMod SHIFT, H, movewindow, l"
        "$mainMod SHIFT, L, movewindow, r"
        "$mainMod SHIFT, K, movewindow, u"
        "$mainMod SHIFT, J, movewindow, d"
        "$mainMod SHIFT, left, movewindow, l"
        "$mainMod SHIFT, right, movewindow, r"
        "$mainMod SHIFT, up, movewindow, u"
        "$mainMod SHIFT, down, movewindow, d"

        # Switch workspaces with mainMod + [0-9]
        "$mainMod, 1, workspace, 1"
        "$mainMod, 2, workspace, 2"
        "$mainMod, 3, workspace, 3"
        "$mainMod, 4, workspace, 4"
        "$mainMod, 5, workspace, 5"
        "$mainMod, 6, workspace, 6"
        "$mainMod, 7, workspace, 7"
        "$mainMod, 8, workspace, 8"
        "$mainMod, 9, workspace, 9"
        "$mainMod, 0, workspace, 10"

        # Move active window to a workspace with mainMod + SHIFT + [0-9]
        "$mainMod SHIFT, 1, movetoworkspace, 1"
        "$mainMod SHIFT, 2, movetoworkspace, 2"
        "$mainMod SHIFT, 3, movetoworkspace, 3"
        "$mainMod SHIFT, 4, movetoworkspace, 4"
        "$mainMod SHIFT, 5, movetoworkspace, 5"
        "$mainMod SHIFT, 6, movetoworkspace, 6"
        "$mainMod SHIFT, 7, movetoworkspace, 7"
        "$mainMod SHIFT, 8, movetoworkspace, 8"
        "$mainMod SHIFT, 9, movetoworkspace, 9"
        "$mainMod SHIFT, 0, movetoworkspace, 10"

        # Special workspace (scratchpad)
        "$mainMod, S, togglespecialworkspace, magic"
        "$mainMod SHIFT, S, movetoworkspace, special:magic"

        # Scroll through existing workspaces with mainMod + scroll
        "$mainMod, mouse_down, workspace, e+1"
        "$mainMod, mouse_up, workspace, e-1"
      ];

      # Repeat binds for multimedia (mit Dunst Progress-Bar Notifications)
      bindel = [
        ", XF86AudioRaiseVolume, exec, wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%+ && ${volumeNotify}"
        ", XF86AudioLowerVolume, exec, wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%- && ${volumeNotify}"
        ", XF86AudioMute, exec, wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle && ${volumeNotify}"
        ", XF86AudioMicMute, exec, wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"
        ", XF86MonBrightnessUp, exec, brightnessctl -e4 -n2 set 5%+ && ${brightnessNotify}"
        ", XF86MonBrightnessDown, exec, brightnessctl -e4 -n2 set 5%- && ${brightnessNotify}"
      ];

      # Lock binds for media control
      bindl = [
        ", XF86AudioNext, exec, playerctl next"
        ", XF86AudioPause, exec, playerctl play-pause"
        ", XF86AudioPlay, exec, playerctl play-pause"
        ", XF86AudioPrev, exec, playerctl previous"
      ];

      # Mouse bindings
      bindm = [
        "$mainMod, mouse:272, movewindow"
        "$mainMod, mouse:273, resizewindow"
      ];

    };
  };

  services.hyprpolkitagent.enable = true;
}
