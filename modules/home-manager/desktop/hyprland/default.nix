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
# - automount.nix - GVFS removable media automount
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
# Keyboard shortcuts (mainMod = Super):
#
# Applications and system:
#   Super+Enter          - Open terminal (Kitty)
#   Super+Q              - Close focused window
#   Super+M              - Open power menu
#   Super+Shift+Q        - Lock screen
#   Super+E              - Open file manager
#   Super+V              - Toggle floating window
#   Super+R              - Open application launcher (Rofi)
#   Super+W              - Open window list (Rofi)
#   Super+B              - Open places (removable media, bookmarks, SMB shares)
#   Super+C              - Open clipboard history
#   Super+Shift+R        - Reload Waybar
#   Alt+K                - Move selection up in Rofi
#   Alt+J                - Move selection down in Rofi
#   Super+P              - Toggle pseudotiling
#   Super+Space          - Toggle split layout
#   Super+F              - Toggle fullscreen
#
# Screenshots:
#   Print                - Capture current output
#   Shift+Print          - Capture a region
#   Super+Shift+Print    - Capture the focused window
#
# Focus and window movement:
#   Super+H/J/K/L        - Focus left/down/up/right
#   Super+Arrow keys     - Focus left/right/up/down
#   Super+Shift+H/J/K/L - Move window left/down/up/right
#   Super+Ctrl+Left/Right - Focus the other monitor
#   Super+Ctrl+H/L      - Resize window horizontally
#   Super+Ctrl+J/K      - Resize window vertically
#   Super+S              - Toggle special workspace "magic"
#   Super+Shift+S        - Move window to special workspace "magic"
#   Super+Wheel down/up  - Switch to next/previous workspace
#
# Workspaces:
#   Super+[1-8]          - Switch to workspace 1-8
#   Super+Shift+[1-8]    - Move window to workspace 1-8
#
# Media and hardware keys (also active while locked where noted):
#   XF86AudioRaiseVolume / XF86AudioLowerVolume - Adjust volume (locked)
#   XF86AudioMute        - Toggle output mute (locked)
#   XF86AudioMicMute     - Toggle microphone mute (locked)
#   XF86MonBrightnessUp/Down - Adjust display brightness (locked)
#   Super+F5 / Super+F6  - Adjust display brightness down/up (locked)
#   XF86AudioNext/Prev   - Next/previous track (locked)
#   XF86AudioPlay/Pause  - Toggle playback (locked)
#   XF86PowerOff         - Suspend when locked, otherwise open power menu
#
# Mouse:
#   Super+Left click     - Move focused window
#   Super+Right click    - Resize focused window

{
  config,
  pkgs,
  lib,
  theme,
  locale,
  i18n,
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
  screenshotSavedTitle = i18n.translate "Screenshot saved" "Screenshot gespeichert";
  screenshotSavedMessage = i18n.translate "Saved to" "Gespeichert unter";
  mediaNowPlaying = i18n.translate "Now playing" "Wird abgespielt";
  mediaPlaying = i18n.translate "Playback resumed" "Wiedergabe fortgesetzt";
  mediaTrackNotify = pkgs.writeShellScript "media-track-notify" ''
    log() {
      printf 'event=%s status=%s detail="%s"\n' "$1" "$2" "$3"
    }
    declare -A last_tracks=()
    declare -A last_statuses=()
    declare -A initialized_players=()
    cache_dir="''${XDG_CACHE_HOME:-$HOME/.cache}/media-track-notify"
    fallback_icon="${theme.icons.package}/share/icons/Papirus/32x32/mimetypes/audio-x-generic.svg"
    mkdir -p "$cache_dir"
    player_icon() {
      local player="$1"
      local icon_name
      case "$player" in
        spotify*) icon_name=spotify ;;
        # Spotify's CEF backend registers an instance-specific Chromium MPRIS
        # player. Keep normal Chromium media sessions separate.
        chromium.instance*) icon_name=spotify ;;
        firefox*) icon_name=firefox ;;
        chromium*) icon_name=chromium ;;
        brave*) icon_name=brave-browser ;;
        vlc*) icon_name=vlc ;;
        elisa*) icon_name=elisa ;;
        mpv*) icon_name=mpv ;;
        *) icon_name="$player" ;;
      esac
      for size in 32x32 48x48 64x64 24x24; do
        for extension in svg png; do
          candidate="${theme.icons.package}/share/icons/Papirus/$size/apps/$icon_name.$extension"
          if [ -f "$candidate" ]; then
            printf '%s\n' "$candidate"
            return 0
          fi
        done
      done
      printf '%s\n' "$fallback_icon"
    }
    log service started "players=all"
    while true; do
      while IFS='|' read -r player status title artist track_id art_url; do
        [ -n "$player" ] || continue
        [ -n "$title" ] || continue
        track_key="$track_id"
        [ -n "$track_key" ] || track_key="$artist - $title"
        previous_track="''${last_tracks[$player]-}"
        previous_status="''${last_statuses[$player]-}"
        last_tracks[$player]="$track_key"
        last_statuses[$player]="$status"
        if [ -z "''${initialized_players[$player]-}" ]; then
          initialized_players[$player]=1
          log track baseline "player=$player"
          continue
        fi
        if [ "$previous_track" = "$track_key" ] && [ "$previous_status" = "$status" ]; then
          continue
        fi
        icon=$(player_icon "$player")
        notification_player="$player"
        [[ "$player" == chromium.instance* ]] && notification_player=spotify
        if [[ "$art_url" == file://* ]]; then
          local_art="''${art_url#file://}"
          [ -f "$local_art" ] && icon="$local_art"
        elif [[ "$art_url" == https://* || "$art_url" == http://* ]]; then
          art_cache="$cache_dir/''${track_key//[^[:alnum:]]/_}.img"
          if [ ! -s "$art_cache" ]; then
            ${pkgs.curl}/bin/curl -fsSL --max-time 10 "$art_url" -o "$art_cache.tmp" 2>/dev/null \
              && ${pkgs.coreutils}/bin/mv "$art_cache.tmp" "$art_cache" \
              || ${pkgs.coreutils}/bin/rm -f "$art_cache.tmp"
          fi
          [ -s "$art_cache" ] && icon="$art_cache"
        fi
        if [ "$previous_track" != "$track_key" ]; then
          log track changed "player=$player track=$track_key"
          notification_title="${mediaNowPlaying}"
          notification_body="$artist - $title"
        elif [ "$status" = "Playing" ]; then
          log playback resumed "player=$player"
          notification_title="${mediaPlaying}"
          notification_body="$artist - $title"
        else
          continue
        fi
        ${pkgs.libnotify}/bin/notify-send -a "$notification_player" -i "$icon" \
          --replace-id=1001 \
          "$notification_title" "$notification_body" \
          && log notification sent "player=$player" \
          || log notification failed "player=$player"
      done < <(${pkgs.coreutils}/bin/stdbuf -oL ${pkgs.playerctl}/bin/playerctl --all-players --follow metadata \
        --format '{{playerName}}|{{status}}|{{title}}|{{artist}}|{{mpris:trackid}}|{{mpris:artUrl}}' 2>/dev/null || true)
      ${pkgs.coreutils}/bin/sleep 2
    done
  '';
  screenshotCommand = mode: ''
    output="${config.xdg.userDirs.pictures}/Screenshot_$(date +%Y%m%d_%H%M%S).png"
    mkdir -p "${config.xdg.userDirs.pictures}"
    saved_files=$(mktemp)
    ${pkgs.inotify-tools}/bin/inotifywait -q -m \
      -e close_write -e moved_to --format '%w%f' \
      --include '\\.png$' "${config.xdg.userDirs.pictures}" > "$saved_files" &
    watcher_pid=$!
    ${pkgs.hyprshot}/bin/hyprshot -m ${mode} --raw \
      | ${pkgs.satty}/bin/satty -f - \
        --copy-command '${pkgs.wl-clipboard}/bin/wl-copy --type image/png' \
        --disable-notifications --early-exit --output-filename "$output"
    satty_status=$?
    kill "$watcher_pid" 2>/dev/null || true
    wait "$watcher_pid" 2>/dev/null || true
    saved_output=""
    while IFS= read -r saved_file; do
      saved_output="$saved_file"
    done < "$saved_files"
    rm -f "$saved_files"
    if [[ "$satty_status" -eq 0 && -f "$saved_output" ]]; then
      ${pkgs.libnotify}/bin/notify-send -u low -i "$saved_output" \
        "${screenshotSavedTitle}" "${screenshotSavedMessage}: $saved_output"
    fi
  '';
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
      mode = "${toString m.width}x${toString m.height}@${toString m.refreshRate}";
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

  brightnessController = import ./scripts/brightness-controller.nix { inherit pkgs i18n theme; };
  displayBrightnessInit = "${brightnessController} init";
  displayBrightness = "${brightnessController} adjust";
  configuredExternalMonitor = lib.findFirst (
    monitor: !(builtins.match "^(eDP|LVDS|DPI|DSI)-.*" monitor.name != null)
  ) null displays.monitors;
  lidDisplayMonitor = pkgs.writeShellScript "hyprland-lid-display-monitor" ''
    lid_devices=()
    for name_file in /sys/class/input/event*/device/name; do
      [ -f "$name_file" ] || continue
      name=$(${pkgs.coreutils}/bin/cat "$name_file")
      if [ "$name" = "Lid Switch" ]; then
        event=$(basename "$(dirname "$(dirname "$name_file")")")
        lid_devices+=("/dev/input/$event")
      fi
    done
    workspace_state="''${XDG_RUNTIME_DIR}/hyprland-lid-workspaces"
    monitor_state="''${XDG_RUNTIME_DIR}/hyprland-lid-monitors"

    state_files=()
    for candidate in /proc/acpi/button/lid/*/state; do
      if [ -f "$candidate" ]; then
        state_files+=("$candidate")
      fi
    done
    [ ''${#lid_devices[@]} -gt 0 ] || [ ''${#state_files[@]} -gt 0 ] || exit 0

    (
      if [ ''${#lid_devices[@]} -gt 0 ]; then
        for lid_device in "''${lid_devices[@]}"; do
          ${pkgs.coreutils}/bin/stdbuf -o0 ${pkgs.evtest}/bin/evtest "$lid_device" 2>/dev/null | while read -r line; do
            case "$line" in
              *"code 0 (SW_LID), value 1"*) printf 'closed\n' ;;
              *"code 0 (SW_LID), value 0"*) printf 'open\n' ;;
            esac
          done &
        done
        while ${pkgs.coreutils}/bin/sleep 3600; do :; done
      else
        previous=open
        for state_file in "''${state_files[@]}"; do
          [ "$(${pkgs.gawk}/bin/awk '{ print $2 }' "$state_file")" = "closed" ] && previous=closed
        done
        while ${pkgs.coreutils}/bin/sleep 0.25; do
          state=open
          for state_file in "''${state_files[@]}"; do
            [ "$(${pkgs.gawk}/bin/awk '{ print $2 }' "$state_file")" = "closed" ] && state=closed
          done
          [ "$state" = "$previous" ] && continue
          previous="$state"
          printf '%s\n' "$state"
        done
      fi
    ) | {
      handled_state=""
      while read -r state; do
        [ "$state" = "$handled_state" ] && continue
        handled_state="$state"
      printf 'lid state changed to %s\n' "$state"

      monitors=$(${pkgs.hyprland}/bin/hyprctl monitors -j) || continue
        internal=$(printf '%s' "$monitors" | ${pkgs.jq}/bin/jq -r '[.[] | .name | select(test("^(eDP|LVDS|DPI|DSI)-"))][0] // empty')
        if [ -z "$internal" ] && [ -f "$monitor_state" ]; then
          internal=$(${pkgs.gawk}/bin/awk 'NR == 1 { print; exit }' "$monitor_state")
        fi
      external=$(printf '%s' "$monitors" | ${pkgs.jq}/bin/jq -r --arg internal "$internal" --arg configured "${
        if configuredExternalMonitor == null then "" else configuredExternalMonitor.name
      }" '[.[] | select(if $configured != "" then .name == $configured else .name != $internal end)][0].name // empty')
      [ -n "$internal" ] && [ -n "$external" ] || continue

      if [ "$state" = "closed" ]; then
        printf '%s\n%s\n' "$internal" "$external" > "$monitor_state"
        ${pkgs.hyprland}/bin/hyprctl workspaces -j | ${pkgs.jq}/bin/jq -r --arg internal "$internal" '.[] | select(.monitor == $internal) | .name' > "$workspace_state"
        while read -r workspace; do
          [ -n "$workspace" ] || continue
          ${pkgs.hyprland}/bin/hyprctl dispatch "hl.dsp.workspace.move({ workspace = \"$workspace\", monitor = \"$external\" })"
        done < "$workspace_state"
        ${pkgs.hyprland}/bin/hyprctl eval "hl.monitor({ output = \"$internal\", disabled = true })"
        ${pkgs.hyprland}/bin/hyprctl dispatch "hl.dsp.focus({ monitor = \"$external\" })"
        ${pkgs.systemd}/bin/systemctl --user try-restart hypr-dock.service
      elif [ "$state" = "open" ]; then
        ${pkgs.hyprland}/bin/hyprctl eval "hl.monitor({ output = \"$internal\", disabled = false })"
        for _ in 1 2 3; do
          ${pkgs.hyprland}/bin/hyprctl dispatch "hl.dsp.dpms({ mode = \"on\", monitor = \"$internal\" })"
          ${pkgs.coreutils}/bin/sleep 1
        done
        ${brightnessController} restore
        if [ -f "$workspace_state" ]; then
          while read -r workspace; do
            [ -n "$workspace" ] || continue
            ${pkgs.hyprland}/bin/hyprctl dispatch "hl.dsp.workspace.move({ workspace = \"$workspace\", monitor = \"$internal\" })"
          done < "$workspace_state"
          rm -f "$workspace_state"
        fi
        rm -f "$monitor_state"
        ${pkgs.hyprland}/bin/hyprctl dispatch "hl.dsp.focus({ monitor = \"$internal\" })"
        ${pkgs.systemd}/bin/systemctl --user try-restart hypr-dock.service
      fi
      done
    }
  '';
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
        -- Monitor dimensions are physical pixels; window sizes use logical pixels.
        local scale = monitor.scale or 1
        hl.dispatch(hl.dsp.window.resize({
          x = math.floor(monitor.width / scale * 0.6),
          y = math.floor(monitor.height / scale * 0.6)
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
  volumeNotify = import ./scripts/volume-notify.nix { inherit pkgs i18n theme; };
  batteryWarning = import ./scripts/battery-warning.nix { inherit pkgs i18n theme; };

  fileManagerCommand =
    if features.desktop.fileManager == "terminal" then "kitty yazi" else "nautilus";

in
{
  #===========================
  # Imports
  #===========================
  # Hyprland-specific modules
  imports = [
    ./automount.nix # GVFS removable media automount
    ./hyprshell.nix # Rust/GTK4 workspace-aware window switcher
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
    # Shared application autostarts become explicit user services here. This
    # gives Hyprland the same declarative lifecycle KDE gets from XDG entries:
    # start with the graphical session, stop with it, and restart failed apps.
    # The short delay lets the Wayland session settle before GUI applications
    # connect to it. Internal services are defined alongside these units below.
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
              # Use an absolute shell path and exec the app so systemd tracks
              # the actual GUI process instead of the delay wrapper.
              ExecStart = "${pkgs.bash}/bin/sh -c 'sleep 3; exec ${app.exec}'";
              Environment = "PATH=/etc/profiles/per-user/${config.home.username}/bin:/run/current-system/sw/bin";
              Type = "exec";
              Restart = "on-failure";
              # Exit code 1 commonly means another instance is already running,
              # so do not turn that normal condition into a restart loop.
              RestartPreventExitStatus = 1;
              RestartSec = 3;
              TimeoutStopSec = 5;
            }
            // lib.optionalAttrs (app.name == "Mumble") {
              ExecStartPre = config.programs.mumble.updateConfig;
              ExecStop = config.programs.mumble.setQuitNormallyCommand;
            };
            Install.WantedBy = [ "graphical-session.target" ];
          };
        }) config.autostart.apps
      )
      // {

        battery-warning = {
          Unit = {
            Description = "Battery warning notifications";
            After = [ "graphical-session.target" ];
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

        # Clipboard history services are long-running session helpers, not
        # entries in the shared application autostart list.
        cliphist-text = {
          Unit = {
            Description = "Clipboard history - text";
            After = [ "graphical-session.target" ];
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
            After = [ "graphical-session.target" ];
            PartOf = [ "graphical-session.target" ];
          };
          Service = {
            ExecStart = "${pkgs.wl-clipboard}/bin/wl-paste --type image --watch ${pkgs.cliphist}/bin/cliphist store";
            Restart = "on-failure";
            TimeoutStopSec = 2;
          };
          Install.WantedBy = [ "graphical-session.target" ];
        };

        media-track-notify = {
          Unit = {
            Description = "Media player track change notifications";
            After = [ "graphical-session.target" ];
            PartOf = [ "graphical-session.target" ];
          };
          Service = {
            ExecStart = mediaTrackNotify;
            Restart = "on-failure";
            RestartSec = 3;
          };
          Install.WantedBy = [ "graphical-session.target" ];
        };

        power-inhibit = {
          Unit = {
            Description = "Power button inhibitor for desktop mode";
            Documentation = "man:systemd-inhibit(1)";
            After = [ "graphical-session.target" ];
            PartOf = [ "graphical-session.target" ];
          };
          Service = {
            ExecStart = "${pkgs.systemd}/bin/systemd-inhibit --what=handle-power-key ${pkgs.uutils-coreutils-noprefix}/bin/sleep infinity";
            Type = "simple";
            TimeoutStopSec = 5;
          };
          Install.WantedBy = [ "graphical-session.target" ];
        };

      }
      // lib.optionalAttrs (features.hardware.formFactor == "laptop") {
        lid-display-monitor = {
          Unit = {
            Description = "Handle laptop lid display switching";
            After = [ "graphical-session.target" ];
            PartOf = [ "graphical-session.target" ];
          };
          Service = {
            ExecStart = lidDisplayMonitor;
            Restart = "on-failure";
            RestartSec = 2;
          };
          Install.WantedBy = [ "graphical-session.target" ];
        };
      };

    # Reduce default stop timeout for user session
    xdg.configFile."systemd/user.conf".text = ''
      [Manager]
      DefaultTimeoutStopSec=10s
    '';

    home = {
      activation = {
        removeLegacyHyprlandConfig = lib.hm.dag.entryBefore [ "checkLinkTargets" ] ''
          rm -f "${config.xdg.configHome}/hypr/hyprland.conf"
        '';

        # Remove a stale Mumble mask before Home Manager owns the user unit.
        removeLegacyMumbleMask = lib.hm.dag.entryBefore [ "checkLinkTargets" ] ''
          ${config.programs.mumble.removeLegacyMask}
        '';
      };

      packages = [
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
    };

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
            "QT_QPA_PLATFORM"
            "wayland"
          ]
          [
            "QT_QPA_PLATFORMTHEME"
            "qt6ct"
          ]
          [
            "QT_STYLE_OVERRIDE"
            "kvantum"
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
            dim_around = 0.0;
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
          match.namespace = "^(rofi|waybar|hypr-dock|hyprshell_switch)$";
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
          (execBind (modKey "B") config.rofi.places)
          (bind (modKey "P") "window.pseudo()")
          (bind (modKey "Space") ''layout("togglesplit")'')
          (bind (modKey "F") ''window.fullscreen({ mode = "maximized" })'')
          (execBind "Print" (screenshotCommand "output"))
          (execBind "SHIFT + Print" (screenshotCommand "region"))
          (execBind (modKey "SHIFT + Print") (screenshotCommand "window"))
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
