# Hyprland Configuration (Home Manager)
#
# This module configures Hyprland window manager and imports all Hyprland-specific modules:
# - theme.nix - Qt/Kvantum theming, hidden window buttons
# - waybar.nix - Status bar
# - rofi.nix - Application launcher, power menu, window switcher
# - awww.nix - Wayland-specific tools (wallpaper, clipboard, screenshots)
# - nautilus.nix - File manager (GNOME Files)
# - hyprlock.nix - Screen locker
# - hypridle.nix - Idle management (auto-lock, screen timeout)
# - dunst.nix - Notification daemon
# - hypr-dock.nix - Application dock
#
# Key features:
# - Multi-monitor support with per-monitor workspaces
# - Keybindings (Super key based)
# - Volume/brightness notifications
# - Battery warnings
# - Window rules and workspace rules
# - Animations and visual effects
#
# Keybindings overview:
#   Super+Q          - Close window
#   Super+M          - Exit Hyprland
#   Super+V          - Toggle floating
#   Super+Space      - Application launcher (rofi)
#   Super+Tab        - Window list
#   Super+[1-9]      - Switch workspace
#   Super+Shift+[1-9] - Move window to workspace
#   Super+F          - Toggle fullscreen
#   Super+C          - Clipboard manager
#   Super+R          - Rofi toggle
#   Super+W          - Window list

{ config, pkgs, lib, theme, fonts, locale, displays, input, ... }:

let
  # ============================================================================
  # MONITOR CONFIGURATION
  # ============================================================================
  # Convert rotation enum to Hyprland transform number
  hyprTransform = rot: { "normal" = "0"; "90" = "1"; "180" = "2"; "270" = "3"; }.${rot};
  rotSuffix = m: if m.rotation == "normal" then "" else ", transform, ${hyprTransform m.rotation}";

  # Generate monitor configuration lines
  # Format: "name, widthxheight@refreshRate, xPos x yPos, scale"
  # Example: "DP-1, 2560x1440@144, 0x0, 1.0"
  monitorLines =
    (map (m:
      "${m.name}, ${toString m.width}x${toString m.height}@${toString m.refreshRate}, ${toString m.x}x${toString m.y}, ${toString m.scale}${rotSuffix m}"
    ) displays.monitors)
    ++ [ ", preferred, auto, ${toString theme.scale}" ];  # Fallback for unknown monitors

  # Workspace bindings: Bind specific workspaces to specific monitors
  # Example: If monitor DP-1 has workspaces [1,2,3], generate:
  # "1, DP-1"
  # "2, DP-1"
  # "3, DP-1"
  workspaceBindings = lib.flatten (map (m:
    map (ws: "${toString ws}, ${m.name}") m.workspaces
  ) displays.monitors);

  # Workspace rules: Assign workspaces to monitors
  # Example: "1, monitor:DP-1"
  workspaceRules = lib.flatten (map (m:
    map (ws: "${toString ws}, monitor:${m.name}") m.workspaces
  ) displays.monitors);

  # ============================================================================
  # VOLUME NOTIFICATION SCRIPT
  # ============================================================================
  # Show volume level and mute status with dunst notification
  # Used by: Media keys (XF86AudioRaiseVolume, XF86AudioLowerVolume, XF86AudioMute)
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

  # ============================================================================
  # BRIGHTNESS NOTIFICATION SCRIPT
  # ============================================================================
  # Show brightness level with dunst notification
  # Used by: Media keys (XF86MonBrightnessUp, XF86MonBrightnessDown)
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

  # ============================================================================
  # BATTERY WARNING SCRIPT
  # ============================================================================
  # Monitor battery level and show warnings/auto-suspend
  #
  # Behavior:
  # - ≤5%: Show critical warning, auto-suspend after 5 seconds
  # - ≤10%: Show warning (once per discharge cycle)
  # - >10% or charging: Reset warning flag
  #
  # Runs as systemd user service, checking every 60 seconds
  batteryWarning = pkgs.writeShellScript "battery-warning" ''
    warned=""
    while true; do
      capacity=$(cat /sys/class/power_supply/BAT*/capacity 2>/dev/null | head -1)
      status=$(cat /sys/class/power_supply/BAT*/status 2>/dev/null | head -1)

      if [ -n "$capacity" ] && [ "$status" = "Discharging" ]; then
        if [ "$capacity" -le 5 ]; then
          ${pkgs.dunst}/bin/dunstify -a "battery" -u critical -t 5000 \
            -h string:x-dunst-stack-tag:battery \
            "󰂃  Akku kritisch" "Gerät wird in den Ruhezustand versetzt."
          sleep 5
          systemctl suspend
        elif [ "$capacity" -le 10 ] && [ -z "$warned" ]; then
          ${pkgs.dunst}/bin/dunstify -a "battery" -u critical -t 15000 \
            -h string:x-dunst-stack-tag:battery \
            "󰁺  Niedriger Akkustand (''${capacity}%)" "Bitte Ladegerät anschließen."
          warned="1"
        fi
      fi

      [ "$status" != "Discharging" ] && warned=""
      sleep 60
    done
  '';

in
{
  #===========================
  # Imports
  #===========================
  # Hyprland-specific modules
  imports = [
    ./theme.nix      # Qt/Kvantum theming, hidden window buttons
    ./waybar.nix     # Status bar
    ./rofi.nix       # Application launcher, power menu, window switcher
    ./awww.nix       # Wayland-specific tools (clipboard, screenshots)
    ./nautilus.nix   # File manager (GNOME Files)
    ./hyprlock.nix   # Screen locker
    ./hypridle.nix   # Idle management (auto-lock, screen timeout)
    ./dunst.nix      # Notification daemon
    ./hypr-dock.nix  # Application dock
  ];

  #===========================
  # Configuration
  #===========================

  config = {
    # Battery warning as systemd service instead of exec-once
    systemd.user.services.battery-warning = {
      Unit = {
        Description = "Battery warning notifications";
        PartOf = [ "graphical-session.target" ];
      };
      Service = {
        ExecStart = "${batteryWarning}";
        Restart = "on-failure";
        TimeoutStopSec = 5;
      };
      Install.WantedBy = [ "graphical-session.target" ];
    };

    # Clipboard history services
    systemd.user.services.cliphist-text = {
      Unit = {
        Description = "Clipboard history - text";
        PartOf = [ "graphical-session.target" ];
      };
      Service = {
        ExecStart = "${pkgs.wl-clipboard}/bin/wl-paste --type text --watch ${pkgs.cliphist}/bin/cliphist store";
        Restart = "on-failure";
        TimeoutStopSec = 2;
      };
      Install.WantedBy = [ "graphical-session.target" ];
    };

    systemd.user.services.cliphist-image = {
      Unit = {
        Description = "Clipboard history - images";
        PartOf = [ "graphical-session.target" ];
      };
      Service = {
        ExecStart = "${pkgs.wl-clipboard}/bin/wl-paste --type image --watch ${pkgs.cliphist}/bin/cliphist store";
        Restart = "on-failure";
        TimeoutStopSec = 2;
      };
      Install.WantedBy = [ "graphical-session.target" ];
    };

    # Reduce default stop timeout for user session
    xdg.configFile."systemd/user.conf".text = ''
      [Manager]
      DefaultTimeoutStopSec=10s
    '';

    home.packages = [
    pkgs.brightnessctl
    pkgs.playerctl
    pkgs.hyprshot
    pkgs.satty
    pkgs.wl-clipboard
    pkgs.cliphist
  ];

  wayland.windowManager.hyprland = {
    enable = true;
    xwayland.enable = true;

    systemd.enable = false;  # UWSM handles session management

    settings = {
      monitor = monitorLines;
      workspace = workspaceRules;
      wsbind = workspaceBindings;

      exec-once = [
        "hyprctl dispatch workspace 1"
        "uwsm-app -- ${config.awww.start}"
      ] ++ (map (app: "uwsm-app -- ${app.exec}") config.autostart.apps);

      env = [
        "XCURSOR_THEME,${theme.cursor.name}"
        "XCURSOR_SIZE,${toString theme.cursor.size}"
        "HYPRCURSOR_THEME,${theme.cursor.name}"
        "HYPRCURSOR_SIZE,${toString theme.cursor.size}"
        "QT_QPA_PLATFORMTHEME,qt6ct"
        "GTK_THEME,catppuccin-${config.catppuccin.flavor}-${config.catppuccin.accent}-standard"
        "HYPRSHOT_DIR,${config.xdg.userDirs.pictures}"
      ];

      cursor.no_hardware_cursors = true;

      input = {
        kb_layout = locale.keyboard;
        kb_variant = "";
        kb_model = "";
        kb_options = "";
        kb_rules = "";

        follow_mouse = 1;
        sensitivity = 0;
        natural_scroll = input.mouse.naturalScroll;

        touchpad = {
          natural_scroll = input.touchpad.naturalScroll;
        };
      };

      gesture = "3, horizontal, workspace";

      general = {
        gaps_in = theme.gaps.inner;
        gaps_out = theme.gaps.outer;
        border_size = theme.border.width;
        "col.active_border" = "$accent";
        "col.inactive_border" = "$surface0";
        resize_on_border = true;
        allow_tearing = false;
        layout = "dwindle";
      };

      decoration = {
        rounding = theme.radius.default;
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

      dwindle = {
        pseudotile = true;
        preserve_split = true;
      };

      master = {
        new_status = "master";
      };

      misc = {
        force_default_wallpaper = 0;
        disable_hyprland_logo = true;
      };

      windowrule = [
        # System authentication
        "match:class ^(org\\.freedesktop\\.impl\\.portal\\.desktop\\.hyprland)$, float on"

        # File operations (Nautilus)
        "match:title ^(File Operation Progress)$, float on"
        "match:title ^(Confirm to replace files)$, float on"

        # Picture-in-Picture
        "match:title ^(Picture-in-Picture)$, float on"
        "match:title ^(Picture-in-Picture)$, pin on"
        "match:title ^(Picture-in-Picture)$, size 25% 25%"

        # Satty (screenshot editor)
        "match:class ^(com\\.gabm\\.satty)$, float on"
        "match:class ^(com\\.gabm\\.satty)$, size 80% 80%"
        "match:class ^(com\\.gabm\\.satty)$, center on"
      ];

      "$mainMod" = "SUPER";

      bind = [
        "$mainMod, Return, exec, kitty"
        "$mainMod, Q, killactive,"
        "$mainMod, M, exec, ${config.rofi.power}"
        "$mainMod SHIFT, Q, exec, hyprlock"
        "$mainMod, E, exec, nautilus"
        # Toggle floating — resize to 60 % of monitor (keeps 16:9 ratio) and center
        "$mainMod, V, exec, hyprctl --batch 'dispatch togglefloating ; dispatch resizeactive exact 60% 60% ; dispatch centerwindow'"
        "$mainMod, R, exec, ${config.rofi.toggle}"
        "$mainMod, W, exec, ${config.rofi.windowList}"
        "$mainMod, P, pseudo,"
        "$mainMod, Space, togglesplit,"
        "$mainMod, F, fullscreen,"

        ", Print, exec, hyprshot -m output --raw | satty -f - --early-exit --output-filename ${config.xdg.userDirs.pictures}/Screenshot_$(date +%Y%m%d_%H%M%S).png"
        "SHIFT, Print, exec, hyprshot -m region --raw | satty -f - --early-exit --output-filename ${config.xdg.userDirs.pictures}/Screenshot_$(date +%Y%m%d_%H%M%S).png"
        "$mainMod SHIFT, Print, exec, hyprshot -m window --raw | satty -f - --early-exit --output-filename ${config.xdg.userDirs.pictures}/Screenshot_$(date +%Y%m%d_%H%M%S).png"
        "$mainMod, C, exec, ${config.rofi.clipboard}"
        "$mainMod, F1, exec, ${config.rofi.powerProfile}"
        "$mainMod SHIFT, R, exec, ${config.waybar.reload}"

        "$mainMod, H, movefocus, l"
        "$mainMod, L, movefocus, r"
        "$mainMod, K, movefocus, u"
        "$mainMod, J, movefocus, d"
        "$mainMod, left, movefocus, l"
        "$mainMod, right, movefocus, r"
        "$mainMod, up, movefocus, u"
        "$mainMod, down, movefocus, d"

        "$mainMod SHIFT, H, movewindow, l"
        "$mainMod SHIFT, L, movewindow, r"
        "$mainMod SHIFT, K, movewindow, u"
        "$mainMod SHIFT, J, movewindow, d"

        "$mainMod CTRL, H, focusmonitor, l"
        "$mainMod CTRL, L, focusmonitor, r"

        "$mainMod, 1, workspace, 1"
        "$mainMod, 2, workspace, 2"
        "$mainMod, 3, workspace, 3"
        "$mainMod, 4, workspace, 4"
        "$mainMod, 5, workspace, 5"
        "$mainMod, 6, workspace, 6"
        "$mainMod, 7, workspace, 7"
        "$mainMod, 8, workspace, 8"
        #"$mainMod, 9, workspace, 9"
        #"$mainMod, 0, workspace, 10"

        "$mainMod SHIFT, 1, movetoworkspace, 1"
        "$mainMod SHIFT, 2, movetoworkspace, 2"
        "$mainMod SHIFT, 3, movetoworkspace, 3"
        "$mainMod SHIFT, 4, movetoworkspace, 4"
        "$mainMod SHIFT, 5, movetoworkspace, 5"
        "$mainMod SHIFT, 6, movetoworkspace, 6"
        "$mainMod SHIFT, 7, movetoworkspace, 7"
        "$mainMod SHIFT, 8, movetoworkspace, 8"
        #"$mainMod SHIFT, 9, movetoworkspace, 9"
        #"$mainMod SHIFT, 0, movetoworkspace, 10"

        "$mainMod, S, togglespecialworkspace, magic"
        "$mainMod SHIFT, S, movetoworkspace, special:magic"
        "$mainMod, mouse_down, workspace, e+1"
        "$mainMod, mouse_up, workspace, e-1"
      ];

      bindel = [
        ", XF86AudioRaiseVolume, exec, wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%+ && ${volumeNotify}"
        ", XF86AudioLowerVolume, exec, wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%- && ${volumeNotify}"
        ", XF86AudioMute, exec, wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle && ${volumeNotify}"
        ", XF86AudioMicMute, exec, wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"
        ", XF86MonBrightnessUp, exec, brightnessctl -e4 -n2 set 5%+ && ${brightnessNotify}"
        ", XF86MonBrightnessDown, exec, brightnessctl -e4 -n2 set 5%- && ${brightnessNotify}"
      ];

      bindl = [
        ", XF86AudioNext, exec, playerctl next"
        ", XF86AudioPause, exec, playerctl play-pause"
        ", XF86AudioPlay, exec, playerctl play-pause"
        ", XF86AudioPrev, exec, playerctl previous"
        ", XF86PowerOff, exec, pidof hyprlock && systemctl suspend || ${config.rofi.power}"
      ];

      bindm = [
        "$mainMod, mouse:272, movewindow"
        "$mainMod, mouse:273, resizewindow"
      ];

    };

  };

  services.hyprpolkitagent.enable = true;
  };
}
