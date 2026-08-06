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
# Brightness control:
# - Laptops: brightnessctl (kernel backlight)
# - Desktops: ddcutil (DDC/CI monitor brightness) with hyprsunset gamma fallback
#   for idle dimming when no DDC-capable monitor is attached
#
# Keybindings overview:
#   Super+Q          - Close window
#   Super+M          - Exit Hyprland
#   Super+V          - Toggle floating
#   Super+Space      - Application launcher (rofi)
#   Super+[1-9]      - Switch workspace
#   Super+Shift+[1-9] - Move window to workspace
#   Super+F          - Toggle maximize
#   Super+Ctrl+H/L   - Resize window horizontally
#   Super+Ctrl+J/K   - Resize window vertically
#   Super+C          - Clipboard manager
#   Super+R          - Rofi toggle
#   Super+W          - Window list

{
  config,
  pkgs,
  lib,
  theme,
  fonts,
  locale,
  displays,
  input,
  features,
  ...
}:

let
  # Convert "App Name" → "app-name" for systemd service names / slugs
  slug = name: builtins.replaceStrings [ " " ] [ "-" ] (lib.toLower name);

  # Catppuccin palette (shared across Hyprland modules via common/theme.nix)
  palette = config.theme.catppuccinPalette;
  stripHash = hex: lib.removePrefix "#" hex;
  accentColor = "rgba(${stripHash palette.${config.catppuccin.accent}.hex}ff)";
  surface0Color = "rgba(${stripHash palette.surface0.hex}ff)";
  displayHelpers = import ../../../lib/displays.nix { inherit lib; };

  # ============================================================================
  # MONITOR CONFIGURATION
  # ============================================================================
  # Convert rotation enum to Hyprland transform number
  hyprTransform =
    rot:
    {
      "normal" = 0;
      "90" = 1;
      "180" = 2;
      "270" = 3;
    }
    .${rot};

  monitorSpecs = [
    {
      output = "";
      mode = "preferred";
      position = "auto";
      inherit (theme) scale;

    }
  ]
  ++ map (
    m:
    {
      output = m.name;
      mode = "preferred";
      position = "${toString m.x}x${toString m.y}";
      inherit (m) scale vrr;
      transform = hyprTransform m.rotation;
    }
    // lib.optionalAttrs (m.hdr == 2) {
      bitdepth = 10;
      cm = "hdredid";
      sdr_max_luminance = m.hdrSdrMaxLuminance;
    }
  ) displays.monitors;

  vrrMode = lib.foldl' (
    mode: monitor: lib.max mode monitor.vrr
  ) displays.defaults.vrr displays.monitors;
  hasHDR = displayHelpers.hasDesktopHDR displays.monitors || displays.defaults.hdr == 2;

  workspaceRules = lib.flatten (
    map (
      m:
      (map (ws: {
        workspace = toString ws;
        monitor = m.name;
      }) m.workspaces)
      ++ lib.optional (m.workspaces != [ ]) {
        workspace = toString (builtins.head m.workspaces);
        monitor = m.name;
        default = true;
      }
    ) displays.monitors
  );

  luaInline = lib.generators.mkLuaInline;
  modKey = key: luaInline ''mainMod .. " + ${key}"'';
  dispatcher = expression: luaInline "hl.dsp.${expression}";
  bind = key: expression: {
    _args = [
      key
      (dispatcher expression)
    ];
  };
  bindWith = options: key: expression: {
    _args = [
      key
      (dispatcher expression)
      options
    ];
  };
  bindCallbackWith = options: key: callback: {
    _args = [
      key
      callback
      options
    ];
  };
  execBind = key: command: bind key "exec_cmd(${builtins.toJSON command})";

  brightnessController = import ./scripts/brightness-controller.nix { inherit pkgs; };
  displayBrightnessInit = "${brightnessController} init";
  displayBrightness = "${brightnessController} adjust";

  toggleFloating = luaInline ''
    function()
      local window = hl.get_active_window()
      if not window then
        return
      end
      if window.floating then
        hl.dispatch(hl.dsp.window.float({ action = "disable" }))
        return
      end

      local monitor = window.monitor or hl.get_active_monitor()
      hl.dispatch(hl.dsp.window.float({ action = "enable" }))
      if monitor then
        hl.dispatch(hl.dsp.window.resize({
          x = math.floor(monitor.width * 0.6),
          y = math.floor(monitor.height * 0.6)
        }))
        hl.dispatch(hl.dsp.window.center())
      end
    end
  '';

  acceleratedResize =
    x: y:
    luaInline ''
      function()
        local state = _G.hyprlandResizeState
        if not state or state.velocity == nil then
          state = { velocity = 0, decayStart = 0, idleTicks = 0, generation = 0 }
        end
        state.velocity = math.min(state.velocity + 0.5, 22)
        state.generation = state.generation + 1
        _G.hyprlandResizeState = state

        if not state.timer then
          local observedGeneration = state.generation
          state.decayStart = state.velocity
          state.timer = hl.timer(function()
            local current = _G.hyprlandResizeState
            if not current then
              return
            end
            if current.generation ~= observedGeneration then
              observedGeneration = current.generation
              current.decayStart = current.velocity
              current.idleTicks = 0
            else
              current.idleTicks = math.min(current.idleTicks + 1, 30)
              current.velocity = current.decayStart * (1 - current.idleTicks / 30)
            end
          end, { timeout = 25, type = "repeat" })
        end

        local step = math.floor(2 + state.velocity)
        hl.dispatch(hl.dsp.window.resize({ x = ${toString x} * step, y = ${toString y} * step, relative = true }))
      end
    '';

  # ============================================================================
  # VOLUME NOTIFICATION SCRIPT
  # ============================================================================
  # Show volume level and mute status with dunst notification
  # Used by: Media keys (XF86AudioRaiseVolume, XF86AudioLowerVolume, XF86AudioMute)
  volumeNotify = import ./scripts/volume-notify.nix { inherit pkgs; };
  batteryWarning = import ./scripts/battery-warning.nix { inherit pkgs; };

  fileManagerCommand =
    if features.desktop.fileManager == "terminal" then "kitty yazi" else "nautilus";

  mumbleSetQuitFlag = pkgs.writeShellScript "mumble-set-quit-flag" ''
    [ -n "''${MAINPID:-}" ] && kill -0 "$MAINPID" 2>/dev/null || exit 0
    config_file="$HOME/.config/Mumble/Mumble/mumble_settings.json"
    [ -f "$config_file" ] || exit 0
    config_dir="$(${pkgs.uutils-coreutils-noprefix}/bin/dirname "$config_file")"
    tmp_file="$(${pkgs.uutils-coreutils-noprefix}/bin/mktemp --tmpdir="$config_dir" .mumble-settings.XXXXXX)" || exit 0
    trap '${pkgs.uutils-coreutils-noprefix}/bin/rm -f "$tmp_file"' EXIT
    if ${pkgs.jq}/bin/jq '.mumble_has_quit_normally = true' "$config_file" > "$tmp_file" \
      && ${pkgs.uutils-coreutils-noprefix}/bin/chmod --reference="$config_file" "$tmp_file"; then
      ${pkgs.uutils-coreutils-noprefix}/bin/mv "$tmp_file" "$config_file"
    fi
  '';

in
{
  #===========================
  # Imports
  #===========================
  # Hyprland-specific modules
  imports = [
    ./theme.nix # Qt/Kvantum theming, hidden window buttons
    ./waybar.nix # Status bar
    ./rofi.nix # Application launcher, power menu, window switcher
    ./awww.nix # Wayland-specific tools (clipboard, screenshots)
    ./hyprlock.nix # Screen locker
    ./hypridle.nix # Idle management (auto-lock, screen timeout)
    ./dunst.nix # Notification daemon
    ./hypr-dock.nix # Application dock
  ]
  ++ lib.optionals (features.desktop.fileManager == "default") [
    ./nautilus.nix # File manager (GNOME Files)
  ];

  #===========================
  # Configuration
  #===========================

  config = {
    # All systemd user services: autostart apps + internal services.
    # Autostart apps: proper lifecycle (start on login, stop on logout, no
    # duplicates on re-login). Internal services: battery-warning, clipboard.
    systemd.user.services =
      # Generate one service per autostart app
      builtins.listToAttrs (
        map (app: {
          name = slug app.name;
          value = {
            Unit = {
              Description = app.name;
              After = [ "graphical-session.target" ];
              PartOf = [ "graphical-session.target" ];
            };
            Service = {
              # Full bash path so systemd always finds it; exec replaces the shell
              # with the app process so systemd tracks the right PID.
              ExecStart = "${pkgs.bash}/bin/sh -c 'sleep 3; exec ${app.exec}'";
              Environment = "PATH=/etc/profiles/per-user/${config.home.username}/bin:/run/current-system/sw/bin";
              Type = "exec";
              Restart = "on-failure";
              # Exit code 1 often means another instance is already running — not a real crash.
              RestartPreventExitStatus = 1;
              RestartSec = 3;
              TimeoutStopSec = 5;
            }
            // lib.optionalAttrs (app.name == "Mumble") {
              ExecStop = "${mumbleSetQuitFlag}";
            };
            Install.WantedBy = [ "graphical-session.target" ];
          };
        }) config.autostart.apps
      )
      // {

        battery-warning = {
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

        display-brightness-init = {
          Unit = {
            Description = "Initialize display brightness control";
            After = [ "graphical-session.target" ];
            PartOf = [ "graphical-session.target" ];
          };
          Service = {
            ExecStart = displayBrightnessInit;
            Type = "oneshot";
          };
          Install.WantedBy = [ "graphical-session.target" ];
        };

        # Clipboard history services
        cliphist-text = {
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

        cliphist-image = {
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

        power-inhibit = {
          Unit = {
            Description = "Power button inhibitor for desktop mode";
            Documentation = "man:systemd-inhibit(1)";
            PartOf = [ "graphical-session.target" ];
          };
          Service = {
            ExecStart = "${pkgs.systemd}/bin/systemd-inhibit --what=handle-power-key ${pkgs.uutils-coreutils-noprefix}/bin/sleep infinity";
            Type = "simple";
            TimeoutStopSec = 5;
          };
          Install.WantedBy = [ "graphical-session.target" ];
        };

      };

    # Reduce default stop timeout for user session
    xdg.configFile."systemd/user.conf".text = ''
      [Manager]
      DefaultTimeoutStopSec=10s
    '';

    home.activation.removeLegacyHyprlandConfig = lib.hm.dag.entryBefore [ "checkLinkTargets" ] ''
      rm -f "${config.xdg.configHome}/hypr/hyprland.conf"
    '';

    home.packages = [
      pkgs.brightnessctl
      pkgs.ddcutil
      pkgs.playerctl
      pkgs.hyprshot
      pkgs.satty
      pkgs.wl-clipboard
      pkgs.cliphist
      # GTK portal must be in the same profile as the Hyprland portal,
      # otherwise xdg-desktop-portal won't find gtk.portal and the
      # Settings interface (dark mode, color-scheme) won't work.
      pkgs.xdg-desktop-portal-gtk
    ];

    wayland.windowManager.hyprland = {
      enable = true;
      xwayland.enable = true;
      configType = "lua";

      systemd.enable = false; # UWSM handles session management

      settings = {
        accent._var = accentColor;
        surface0._var = surface0Color;
        mainMod._var = "SUPER";

        monitor = monitorSpecs;
        workspace_rule = workspaceRules;

        on._args = [
          "hyprland.start"
          (luaInline ''
            function()
              hl.exec_cmd("hyprctl dispatch workspace 1")
            end
          '')
        ];

        env = map (entry: { _args = entry; }) [
          [
            "XCURSOR_THEME"
            theme.cursor.name
          ]
          [
            "XCURSOR_SIZE"
            (toString theme.cursor.size)
          ]
          [
            "HYPRCURSOR_THEME"
            theme.cursor.name
          ]
          [
            "HYPRCURSOR_SIZE"
            (toString theme.cursor.size)
          ]
          [
            "QT_QPA_PLATFORMTHEME"
            "gnome"
          ]
          [
            "GTK_THEME"
            "catppuccin-${config.catppuccin.flavor}-${config.catppuccin.accent}-standard"
          ]
          [
            "HYPRSHOT_DIR"
            config.xdg.userDirs.pictures
          ]
        ];

        gesture = {
          fingers = 3;
          direction = "horizontal";
          action = "workspace";
        };

        config = {
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
            touchpad.natural_scroll = input.touchpad.naturalScroll;
          };

          general = {
            gaps_in = theme.gaps.inner;
            gaps_out = theme.gaps.outer;
            border_size = theme.border.width;
            col = {
              active_border = luaInline "accent";
              inactive_border = luaInline "surface0";
            };
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
              size = 8;
              passes = 3;
              vibrancy = 0.0;
            };
          };

          animations.enabled = true;

          dwindle = {
            preserve_split = true;
            split_width_multiplier = 1.0;
          };

          master.new_status = "master";

          misc = {
            force_default_wallpaper = 0;
            disable_hyprland_logo = true;
            vrr = vrrMode;
          };

          ecosystem.no_update_news = true;

          render = {
            direct_scanout = 0;
            non_shader_cm = 0;
          }
          // lib.optionalAttrs hasHDR {
            cm_enabled = true;
            cm_sdr_eotf = "gamma22";
          };
        };

        curve = map (curve: { _args = curve; }) [
          [
            "easeOutQuint"
            {
              type = "bezier";
              points = [
                [
                  0.23
                  1
                ]
                [
                  0.32
                  1
                ]
              ];
            }
          ]
          [
            "easeInOutCubic"
            {
              type = "bezier";
              points = [
                [
                  0.65
                  0.05
                ]
                [
                  0.36
                  1
                ]
              ];
            }
          ]
          [
            "linear"
            {
              type = "bezier";
              points = [
                [
                  0
                  0
                ]
                [
                  1
                  1
                ]
              ];
            }
          ]
          [
            "almostLinear"
            {
              type = "bezier";
              points = [
                [
                  0.5
                  0.5
                ]
                [
                  0.75
                  1
                ]
              ];
            }
          ]
          [
            "quick"
            {
              type = "bezier";
              points = [
                [
                  0.15
                  0
                ]
                [
                  0.1
                  1
                ]
              ];
            }
          ]
        ];

        animation = [
          {
            leaf = "global";
            enabled = true;
            speed = 10;
            bezier = "default";
          }
          {
            leaf = "border";
            enabled = true;
            speed = 5.5;
            bezier = "easeOutQuint";
          }
          {
            leaf = "windows";
            enabled = true;
            speed = 5.5;
            bezier = "easeOutQuint";
          }
          {
            leaf = "windowsIn";
            enabled = true;
            speed = 5;
            bezier = "easeOutQuint";
            style = "popin 87%";
          }
          {
            leaf = "windowsOut";
            enabled = true;
            speed = 3.5;
            bezier = "easeOutQuint";
            style = "popin 87%";
          }
          {
            leaf = "windowsMove";
            enabled = true;
            speed = 6;
            bezier = "easeOutQuint";
          }
          {
            leaf = "fadeIn";
            enabled = true;
            speed = 3;
            bezier = "easeOutQuint";
          }
          {
            leaf = "fadeOut";
            enabled = true;
            speed = 3;
            bezier = "easeOutQuint";
          }
          {
            leaf = "fade";
            enabled = true;
            speed = 4;
            bezier = "quick";
          }
          {
            leaf = "fadeSwitch";
            enabled = true;
            speed = 4;
            bezier = "easeOutQuint";
          }
          {
            leaf = "layers";
            enabled = true;
            speed = 5;
            bezier = "easeOutQuint";
          }
          {
            leaf = "layersIn";
            enabled = true;
            speed = 5;
            bezier = "easeOutQuint";
            style = "fade";
          }
          {
            leaf = "layersOut";
            enabled = true;
            speed = 4;
            bezier = "easeOutQuint";
            style = "fade";
          }
          {
            leaf = "fadeLayersIn";
            enabled = true;
            speed = 3;
            bezier = "easeOutQuint";
          }
          {
            leaf = "fadeLayersOut";
            enabled = true;
            speed = 3;
            bezier = "easeOutQuint";
          }
          {
            leaf = "fadePopupsIn";
            enabled = true;
            speed = 4;
            bezier = "easeOutQuint";
          }
          {
            leaf = "fadePopupsOut";
            enabled = true;
            speed = 4;
            bezier = "easeOutQuint";
          }
          {
            leaf = "fadeDpms";
            enabled = true;
            speed = 4;
            bezier = "easeOutQuint";
          }
          {
            leaf = "workspaces";
            enabled = true;
            speed = 3.5;
            bezier = "easeOutQuint";
            style = "slidefade";
          }
          {
            leaf = "workspacesIn";
            enabled = true;
            speed = 3.5;
            bezier = "easeOutQuint";
            style = "slidefade";
          }
          {
            leaf = "workspacesOut";
            enabled = true;
            speed = 3.5;
            bezier = "easeOutQuint";
            style = "slidefade";
          }
          {
            leaf = "specialWorkspace";
            enabled = true;
            speed = 3.5;
            bezier = "easeOutQuint";
            style = "slidefadevert";
          }
          {
            leaf = "specialWorkspaceIn";
            enabled = true;
            speed = 3.5;
            bezier = "easeOutQuint";
            style = "slidefadevert";
          }
          {
            leaf = "specialWorkspaceOut";
            enabled = true;
            speed = 3.5;
            bezier = "easeOutQuint";
            style = "slidefadevert";
          }
          {
            leaf = "zoomFactor";
            enabled = true;
            speed = 6;
            bezier = "easeOutQuint";
          }
        ];

        layer_rule = {
          match.namespace = "^(rofi|waybar|hypr-dock)$";
          blur = true;
          blur_popups = true;
          ignore_alpha = 0.2;
        };

        window_rule = [
          {
            match.class = "^(org\\.freedesktop\\.impl\\.portal\\.desktop\\.hyprland)$";
            float = true;
          }
          {
            match.title = "^(File Operation Progress)$";
            float = true;
          }
          {
            match.title = "^(Confirm to replace files)$";
            float = true;
          }
          {
            match.title = "^(Picture-in-Picture)$";
            float = true;
            pin = true;
            size = "25% 25%";
          }
        ];

        bind = [
          (execBind (modKey "Return") "kitty")
          (bind (modKey "Q") "window.close()")
          (execBind (modKey "M") config.rofi.power)
          (execBind (modKey "SHIFT + Q") "hyprlock")
          (execBind (modKey "E") fileManagerCommand)
          (bindCallbackWith { } (modKey "V") toggleFloating)
          (execBind (modKey "R") config.rofi.toggle)
          (execBind (modKey "W") config.rofi.windowList)
          (bind (modKey "P") "window.pseudo()")
          (bind (modKey "Space") ''layout("togglesplit")'')
          (bind (modKey "F") ''window.fullscreen({ mode = "maximized" })'')
          (execBind "Print" "hyprshot -m output --raw | satty -f - --copy-command '${pkgs.wl-clipboard}/bin/wl-copy --type image/png' --early-exit --output-filename ${config.xdg.userDirs.pictures}/Screenshot_$(date +%Y%m%d_%H%M%S).png")
          (execBind "SHIFT + Print" "hyprshot -m region --raw | satty -f - --copy-command '${pkgs.wl-clipboard}/bin/wl-copy --type image/png' --early-exit --output-filename ${config.xdg.userDirs.pictures}/Screenshot_$(date +%Y%m%d_%H%M%S).png")
          (execBind (modKey "SHIFT + Print") "hyprshot -m window --raw | satty -f - --copy-command '${pkgs.wl-clipboard}/bin/wl-copy --type image/png' --early-exit --output-filename ${config.xdg.userDirs.pictures}/Screenshot_$(date +%Y%m%d_%H%M%S).png")
          (execBind (modKey "C") config.rofi.clipboard)
          (execBind (modKey "SHIFT + R") config.waybar.reload)
          (bind (modKey "H") ''focus({ direction = "left" })'')
          (bind (modKey "L") ''focus({ direction = "right" })'')
          (bind (modKey "K") ''focus({ direction = "up" })'')
          (bind (modKey "J") ''focus({ direction = "down" })'')
          (bind (modKey "left") ''focus({ direction = "left" })'')
          (bind (modKey "right") ''focus({ direction = "right" })'')
          (bind (modKey "up") ''focus({ direction = "up" })'')
          (bind (modKey "down") ''focus({ direction = "down" })'')
          (bind (modKey "SHIFT + H") ''window.move({ direction = "left" })'')
          (bind (modKey "SHIFT + L") ''window.move({ direction = "right" })'')
          (bind (modKey "SHIFT + K") ''window.move({ direction = "up" })'')
          (bind (modKey "SHIFT + J") ''window.move({ direction = "down" })'')
          (bind (modKey "CTRL + left") ''focus({ monitor = "l" })'')
          (bind (modKey "CTRL + right") ''focus({ monitor = "r" })'')
          (bind (modKey "S") ''workspace.toggle_special("magic")'')
          (bind (modKey "SHIFT + S") ''window.move({ workspace = "special:magic" })'')
          (bind (modKey "mouse_down") ''focus({ workspace = "e+1" })'')
          (bind (modKey "mouse_up") ''focus({ workspace = "e-1" })'')
          (bindCallbackWith {
            repeating = true;
          } (modKey "CTRL + H") (acceleratedResize (-1) 0))
          (bindCallbackWith {
            repeating = true;
          } (modKey "CTRL + L") (acceleratedResize 1 0))
          (bindCallbackWith {
            repeating = true;
          } (modKey "CTRL + K") (acceleratedResize 0 (-1)))
          (bindCallbackWith {
            repeating = true;
          } (modKey "CTRL + J") (acceleratedResize 0 1))
          (bindWith
            {
              locked = true;
              repeating = true;
            }
            "XF86AudioRaiseVolume"
            "exec_cmd(${builtins.toJSON "wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%+ && ${volumeNotify}"})"
          )
          (bindWith
            {
              locked = true;
              repeating = true;
            }
            "XF86AudioLowerVolume"
            "exec_cmd(${builtins.toJSON "wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%- && ${volumeNotify}"})"
          )
          (bindWith
            {
              locked = true;
              repeating = true;
            }
            "XF86AudioMute"
            "exec_cmd(${builtins.toJSON "wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle && ${volumeNotify}"})"
          )
          (bindWith {
            locked = true;
            repeating = true;
          } "XF86AudioMicMute" ''exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle")'')
          (bindWith {
            locked = true;
            repeating = true;
          } "XF86MonBrightnessUp" "exec_cmd(${builtins.toJSON "${displayBrightness} up"})")
          (bindWith {
            locked = true;
            repeating = true;
          } "XF86MonBrightnessDown" "exec_cmd(${builtins.toJSON "${displayBrightness} down"})")
          (bindWith {
            locked = true;
            repeating = true;
          } (modKey "F5") "exec_cmd(${builtins.toJSON "${displayBrightness} down"})")
          (bindWith {
            locked = true;
            repeating = true;
          } (modKey "F6") "exec_cmd(${builtins.toJSON "${displayBrightness} up"})")
          (bindWith { locked = true; } "XF86AudioNext" ''exec_cmd("playerctl next")'')
          (bindWith { locked = true; } "XF86AudioPause" ''exec_cmd("playerctl play-pause")'')
          (bindWith { locked = true; } "XF86AudioPlay" ''exec_cmd("playerctl play-pause")'')
          (bindWith { locked = true; } "XF86AudioPrev" ''exec_cmd("playerctl previous")'')
          (bindWith { locked = true; } "XF86PowerOff"
            "exec_cmd(${builtins.toJSON "pidof hyprlock && systemctl suspend || ${config.rofi.power}"})"
          )
          (bindWith { mouse = true; } (modKey "mouse:272") "window.drag()")
          (bindWith { mouse = true; } (modKey "mouse:273") "window.resize()")
        ]
        ++ map (ws: bind (modKey (toString ws)) "focus({ workspace = ${toString ws} })") (lib.range 1 8)
        ++ map (ws: bind (modKey "SHIFT + ${toString ws}") "window.move({ workspace = ${toString ws} })") (
          lib.range 1 8
        );

      };

    };

    services.hyprpolkitagent.enable = true;
  };
}
