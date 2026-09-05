# SDDM System Configuration
#
# Configures SDDM as the login screen for both KDE Plasma and Hyprland.
#
# It provides the KWin Wayland greeter, shared theming, login mode, monitor
# layout, and the on-screen keyboard. KWin applies output scaling directly.
# A complete known monitor setup receives the declared layout; incomplete or
# unknown setups use KWin's automatic detection.

{
  config,
  pkgs,
  lib,
  ...
}:

let
  inherit (config.displays) monitors;

  blurredWallpaper = config.theme.blurredWallpaperPath;

  cursorTheme = config.theme.cursor.name;
  cursorSize = config.theme.cursor.size;
  uiFont = config.fonts.ui.font;

  capitalize =
    s: (lib.toUpper (builtins.substring 0 1 s)) + (builtins.substring 1 (builtins.stringLength s) s);
  colorSchemeId = "Catppuccin${capitalize config.theme.catppuccin.flavor}${capitalize config.theme.catppuccin.accent}";
  catppuccinColorsFile = "${
    pkgs.catppuccin-kde.override {
      flavour = [ config.theme.catppuccin.flavor ];
      accents = [ config.theme.catppuccin.accent ];
    }
  }/share/color-schemes/${colorSchemeId}.colors";
  sddmKdeglobals = pkgs.writeText "sddm-kdeglobals" ''
    [General]
    ColorScheme=${colorSchemeId}
  '';

  catppuccinFlavorColors =
    (lib.importJSON "${config.catppuccin.sources.palette}/palette.json")
    .${config.theme.catppuccin.flavor}.colors;
  catppuccinBase = lib.removePrefix "#" catppuccinFlavorColors.base.hex;
  catppuccinSurface0 = lib.removePrefix "#" catppuccinFlavorColors.surface0.hex;
  catppuccinSurface1 = lib.removePrefix "#" catppuccinFlavorColors.surface1.hex;
  catppuccinText = lib.removePrefix "#" catppuccinFlavorColors.text.hex;
  catppuccinAccentColor =
    lib.removePrefix "#"
      catppuccinFlavorColors.${config.theme.catppuccin.accent}.hex;

  sddmMaliitKeyboard = pkgs.maliit-keyboard.overrideAttrs (oldAttrs: {
    postInstall = (oldAttrs.postInstall or "") + ''
        substituteInPlace "$out/lib/maliit/keyboard2/qml/keys/CharKey.qml" \
          --replace-fail '            hoverEnabled: false' '            hoverEnabled: false

              background: Rectangle {
                  color: keyButton.down ? "#${catppuccinSurface1}" : "#${catppuccinSurface0}"
                  radius: ${toString config.theme.radius.small}
              }'
      ${pkgs.buildPackages.python3}/bin/python3 <<'SPACEKEY'
      import os
      from pathlib import Path
      path = Path(os.environ["out"]) / "lib/maliit/keyboard2/qml/keys/SpaceKey.qml"
      text = path.read_text()
      for old, new in [
          ('    Rectangle {\n        anchors.margins: 8\n        anchors.fill: parent\n        color: "#888888"\n        radius: 8 / Screen.devicePixelRatio\n        opacity: spaceKey.currentlyPressed ? 0.0 : 0.25\n    }',
           '    Rectangle {\n        visible: false\n        anchors.margins: 8\n        anchors.fill: parent\n        color: "#888888"\n        radius: 8 / Screen.devicePixelRatio\n        opacity: spaceKey.currentlyPressed ? 0.0 : 0.25\n    }'),
          ('        opacity: 0.6',
           '        color: "#${catppuccinText}"\n        opacity: 1.0'),
      ]:
          if text.count(old) != 1:
              raise RuntimeError(f"unexpected SpaceKey pattern count: {text.count(old)}")
          text = text.replace(old, new, 1)
      path.write_text(text)
      SPACEKEY
    '';
  });

  deploySddmColors = pkgs.writeShellScript "deploy-sddm-colors" ''
    set -eu
    colors_src="$1"
    colors_name="$2"
    kdeglobals_src="$3"

    ${pkgs.coreutils}/bin/mkdir -p /var/lib/sddm/.config
    ${pkgs.coreutils}/bin/mkdir -p /var/lib/sddm/.local/share/color-schemes
    ${pkgs.coreutils}/bin/ln -sf "$colors_src" "/var/lib/sddm/.local/share/color-schemes/$colors_name.colors"
    ${pkgs.coreutils}/bin/cp "$kdeglobals_src" /var/lib/sddm/.config/kdeglobals
    ${pkgs.coreutils}/bin/chown -R sddm:sddm /var/lib/sddm/.config /var/lib/sddm/.local/share
  '';
  sddmGreeterEnvironment = lib.concatStringsSep "," [
    "QT_WAYLAND_SHELL_INTEGRATION=layer-shell"
    "XCURSOR_THEME=${cursorTheme}"
    "XCURSOR_SIZE=${toString cursorSize}"
  ];

  kscreen = import ../../lib/kscreen.nix { inherit lib; };

  kdeTransform =
    rot:
    {
      "normal" = "Normal";
      "90" = "Rotated90";
      "180" = "Rotated180";
      "270" = "Rotated270";
    }
    .${rot};

  monitorsByPosition = lib.sort (a: b: a.x < b.x || (a.x == b.x && a.y < b.y)) monitors;
  monitorPriorities = lib.listToAttrs (
    lib.imap0 (i: m: lib.nameValuePair m.name i) monitorsByPosition
  );
  sddmKscreenArgs = kscreen.monitorArgs {
    inherit monitors;
    enableHDR = false;
  };

  sddmDisplayConfigFile = pkgs.writeText "kwinoutputconfig.json" (
    builtins.toJSON [
      {
        name = "outputs";
        data = map (m: {
          connectorName = m.name;
          mode = {
            inherit (m) width height;
            refreshRate = m.refreshRate * 1000;
          };
          inherit (m) scale;
          transform = kdeTransform m.rotation;
          overscan = 0;
          rgbRange = "Automatic";
          vrrPolicy =
            if m.vrr == 1 then
              "Always"
            else if m.vrr == 2 then
              "Automatic"
            else
              "Never";
        }) monitorsByPosition;
      }
      {
        name = "setups";
        data = [
          {
            lidClosed = false;
            outputs = lib.imap0 (i: m: {
              enabled = true;
              outputIndex = i;
              position = { inherit (m) x y; };
              priority = monitorPriorities.${m.name};
            }) monitorsByPosition;
          }
        ];
      }
    ]
  );

  configuredOutputNames = lib.escapeShellArgs (map (m: m.name) monitors);
  monitorsWithEdid = lib.filter (m: m.edidHash != null) monitors;
  shouldManageSddmLayout =
    monitors != [ ] && (monitorsWithEdid == [ ] || monitorsWithEdid == monitors);
  # The SDDM greeter always runs on KWin, even when the selected user session
  # is Hyprland. Apply the connector-specific layout in both cases.
  shouldApplySddmLayout = shouldManageSddmLayout;
  configuredOutputEdids = lib.escapeShellArgs (map (m: "${m.name}:${m.edidHash}") monitorsWithEdid);
  configuredOutputEdidChecks = lib.optionalString (monitorsWithEdid != [ ]) ''
    for identity in ${configuredOutputEdids}; do
      output=''${identity%%:*}
      expected_edid=''${identity#*:}
      matched_edid=0

      for edid_file in /sys/class/drm/*-"$output"/edid; do
        status_file=''${edid_file%/edid}/status
        if [ -s "$edid_file" ] && [ -e "$status_file" ] && [ "$(${pkgs.coreutils}/bin/cat "$status_file")" = connected ]; then
          actual_edid=$(${pkgs.uutils-coreutils-noprefix}/bin/sha256sum "$edid_file" | ${pkgs.uutils-coreutils-noprefix}/bin/cut -d' ' -f1)
          if [ "$actual_edid" = "$expected_edid" ]; then
            matched_edid=1
          fi
        fi
      done

      if [ "$matched_edid" -ne 1 ]; then
        all_connected=0
      fi
    done
  '';

  configureSddmDisplays = pkgs.writeShellScript "configure-sddm-displays" ''
    set -e

    config_dir=/var/lib/sddm/.config
    config_file=$config_dir/kwinoutputconfig.json

     ${pkgs.coreutils}/bin/mkdir -p "$config_dir"
     ${pkgs.coreutils}/bin/chown sddm:sddm "$config_dir"
     ${pkgs.coreutils}/bin/chmod 0755 "$config_dir"

    all_connected=1
    for output in ${configuredOutputNames}; do
      connected=0
      for status_file in /sys/class/drm/*-"$output"/status; do
         if [ -e "$status_file" ] && [ "$(${pkgs.coreutils}/bin/cat "$status_file")" = connected ]; then
          connected=1
        fi
      done

      if [ "$connected" -ne 1 ]; then
        all_connected=0
      fi
    done

    ${configuredOutputEdidChecks}

    if [ "$all_connected" -eq 1 ]; then
       ${pkgs.coreutils}/bin/install -o sddm -g sddm -m 0644 ${sddmDisplayConfigFile} "$config_file"
    else
       ${pkgs.coreutils}/bin/rm -f "$config_file"
    fi
  '';

  applySddmDisplayConfig = pkgs.writeShellScript "apply-sddm-display-config" ''
    set -eu

    sddm_uid=$(${pkgs.uutils-coreutils-noprefix}/bin/id -u sddm)
    export XDG_RUNTIME_DIR=/run/user/$sddm_uid
    export DBUS_SESSION_BUS_ADDRESS=unix:path=$XDG_RUNTIME_DIR/bus

    echo "apply-sddm-display-config: waiting for sddm session bus (uid=$sddm_uid)" >&2
    bus_ready=0
    for attempt in $(${pkgs.uutils-coreutils-noprefix}/bin/seq 1 600); do
      if [ -S "$XDG_RUNTIME_DIR/bus" ]; then
        bus_ready=1
        break
      fi
      ${pkgs.uutils-coreutils-noprefix}/bin/sleep 0.1
    done
    if [ "$bus_ready" -ne 1 ]; then
      echo "apply-sddm-display-config: sddm session bus never appeared, giving up" >&2
      exit 0
    fi

    echo "apply-sddm-display-config: bus ready, waiting for KWin D-Bus…" >&2
    for attempt in $(${pkgs.uutils-coreutils-noprefix}/bin/seq 1 300); do
      if ${pkgs.dbus}/bin/dbus-send --session \
        --dest=org.freedesktop.DBus --type=method_call --print-reply \
        /org/freedesktop/DBus org.freedesktop.DBus.ListNames \
        2>/dev/null | ${pkgs.gnugrep}/bin/grep -q org.kde.KWin; then
        break
      fi
      ${pkgs.uutils-coreutils-noprefix}/bin/sleep 0.1
    done

    retry=0
    while [ "$retry" -lt 50 ]; do
      for socket in "$XDG_RUNTIME_DIR"/wayland-*; do
        [ -S "$socket" ] || continue
        case "$socket" in *.lock) continue ;; esac
        export WAYLAND_DISPLAY=$(${pkgs.uutils-coreutils-noprefix}/bin/basename "$socket")
        if ${pkgs.kdePackages.libkscreen}/bin/kscreen-doctor ${sddmKscreenArgs} 2>/dev/null; then
          echo "apply-sddm-display-config: done" >&2
          exit 0
        fi
      done
      retry=$((retry + 1))
      ${pkgs.uutils-coreutils-noprefix}/bin/sleep 0.1
    done

    echo "apply-sddm-display-config: kscreen-doctor failed after retries" >&2
  '';

  sddmThemeName = "catppuccin-${config.catppuccin.sddm.flavor}-${config.catppuccin.sddm.accent}";

  sddmKwinrc = pkgs.writeText "sddm-kwinrc" ''
    [VirtualKeyboard]
    VirtualKeyboardEnabled=true
    VirtualKeyboardMode=0
  '';

  sddmOsk = pkgs.writeShellScript "sddm-osk" ''
    set -u

    export HOME=/var/lib/sddm
    export XDG_CONFIG_HOME=$HOME/.config
    export XDG_DATA_HOME=$HOME/.local/share
    export XDG_RUNTIME_DIR=/run/user/$(${pkgs.uutils-coreutils-noprefix}/bin/id -u sddm)
    export DBUS_SESSION_BUS_ADDRESS=unix:path=$XDG_RUNTIME_DIR/bus
    export GSETTINGS_BACKEND=keyfile
    export GSETTINGS_SCHEMA_DIR="${sddmMaliitKeyboard}/share/gsettings-schemas/${sddmMaliitKeyboard.name}/glib-2.0/schemas"
    export XDG_DATA_DIRS="${pkgs.kdePackages.breeze-icons}/share''${XDG_DATA_DIRS:+:$XDG_DATA_DIRS}"
    export QT_QUICK_CONTROLS_STYLE=Material

    gsettings_dir="$XDG_CONFIG_HOME/glib-2.0/settings"
    ${pkgs.coreutils}/bin/mkdir -p "$gsettings_dir"
    printf '%s\n' \
      '[org/maliit/keyboard/maliit]' \
      "active-language='${config.locale.keyboard}'" \
      "enabled-languages=['${config.locale.keyboard}','en']" \
      "theme='breeze'" \
      > "$gsettings_dir/keyfile"

    qtquick_dir="$XDG_CONFIG_HOME/QtProject"
    ${pkgs.coreutils}/bin/mkdir -p "$qtquick_dir"
    printf '%s\n' \
      '[Controls]' \
      'Style=Material' \
      ' ' \
      '[Material]' \
      'Theme=Dark' \
      'Variant=Dense' \
      'Background=#${catppuccinBase}' \
      'Foreground=#${catppuccinText}' \
      'Primary=#${catppuccinAccentColor}' \
      'Accent=#${catppuccinAccentColor}' \
      > "$qtquick_dir/qtquickcontrols2.conf"
    export QT_QUICK_CONTROLS_CONF="$qtquick_dir/qtquickcontrols2.conf"

    physical_keyboard_present() {
      for event in /sys/class/input/event*; do
        [ -r "$event/dev" ] || continue
        device_number=$(<"$event/dev")
        properties="/run/udev/data/c$device_number"
        [ -r "$properties" ] || continue
        ${pkgs.gnugrep}/bin/grep -qx 'E:ID_INPUT_KEYBOARD=1' "$properties" || continue
        model=$(${pkgs.gnugrep}/bin/grep -m1 '^E:ID_MODEL=' "$properties" | ${pkgs.uutils-coreutils-noprefix}/bin/cut -d= -f2- || true)
        case "$model" in
          *Controller* | *Puck* | *Gamepad* | *Joystick* | *YubiKey*) continue ;;
        esac
        return 0
      done
      return 1
    }

    set_virtual_keyboard() {
      mode=$1
      if [ "$mode" -eq 0 ]; then
        ${pkgs.dbus}/bin/dbus-send --session --reply-timeout=1000 \
          --dest=org.kde.KWin --type=method_call --print-reply \
          /VirtualKeyboard org.freedesktop.DBus.Properties.Set \
          string:"org.kde.kwin.VirtualKeyboard" string:"active" variant:boolean:false \
          >/dev/null 2>&1 || return 1
      fi
      ${pkgs.dbus}/bin/dbus-send --session --reply-timeout=1000 \
        --dest=org.kde.KWin --type=method_call --print-reply \
        /VirtualKeyboard org.freedesktop.DBus.Properties.Set \
        string:"org.kde.kwin.VirtualKeyboard" string:"mode" variant:int32:"$mode" \
        >/dev/null 2>&1 || return 1
      if [ "$mode" -eq 2 ]; then
        ${pkgs.dbus}/bin/dbus-send --session --reply-timeout=1000 \
          --dest=org.kde.KWin --type=method_call --print-reply \
          /VirtualKeyboard org.kde.kwin.VirtualKeyboard.forceActivate \
          >/dev/null 2>&1 || return 1
      fi
    }

    current_keyboard_state() {
      if physical_keyboard_present; then
        printf '%s\n' 0
      else
        printf '%s\n' 2
      fi
    }

    maliit_pid=""

    stop_maliit() {
      [ -z "$maliit_pid" ] && return
      kill "$maliit_pid" 2>/dev/null || true
      for _ in $(${pkgs.uutils-coreutils-noprefix}/bin/seq 1 10); do
        kill -0 "$maliit_pid" 2>/dev/null || break
        ${pkgs.uutils-coreutils-noprefix}/bin/sleep 0.1
      done
      kill -KILL "$maliit_pid" 2>/dev/null || true
      wait "$maliit_pid" 2>/dev/null || true
      maliit_pid=""
    }

    cleanup() {
      trap - EXIT INT TERM
      stop_maliit
      exit 0
    }

    trap cleanup EXIT INT TERM

    while true; do
      bus_ready=0
      for attempt in $(${pkgs.uutils-coreutils-noprefix}/bin/seq 1 600); do
        if [ -S "$XDG_RUNTIME_DIR/bus" ]; then
          bus_ready=1
          break
        fi
        ${pkgs.uutils-coreutils-noprefix}/bin/sleep 0.1
      done
      [ "$bus_ready" -eq 1 ] || { ${pkgs.uutils-coreutils-noprefix}/bin/sleep 1; continue; }

      wayland_display=""
      for attempt in $(${pkgs.uutils-coreutils-noprefix}/bin/seq 1 300); do
        for socket in "$XDG_RUNTIME_DIR"/wayland-*; do
          [ -S "$socket" ] || continue
          case "$socket" in *.lock) continue ;; esac
          wayland_display=$(${pkgs.uutils-coreutils-noprefix}/bin/basename "$socket")
          ${pkgs.dbus}/bin/dbus-send --session --reply-timeout=500 \
            --dest=org.freedesktop.DBus --type=method_call --print-reply \
            /org/freedesktop/DBus org.freedesktop.DBus.ListNames \
            2>/dev/null | ${pkgs.gnugrep}/bin/grep -q org.kde.KWin && break 2
        done
        wayland_display=""
        ${pkgs.uutils-coreutils-noprefix}/bin/sleep 0.2
      done
      [ -n "$wayland_display" ] || { ${pkgs.uutils-coreutils-noprefix}/bin/sleep 1; continue; }

      QT_QPA_PLATFORM=wayland WAYLAND_DISPLAY=$wayland_display ${lib.getExe' sddmMaliitKeyboard "maliit-keyboard"} &
      maliit_pid=$!
      applied_state=-1

      while [ -S "$XDG_RUNTIME_DIR/bus" ] && [ -S "$XDG_RUNTIME_DIR/$wayland_display" ]; do
        if ! kill -0 "$maliit_pid" 2>/dev/null; then
          wait "$maliit_pid" 2>/dev/null || true
          QT_QPA_PLATFORM=wayland WAYLAND_DISPLAY=$wayland_display ${lib.getExe' sddmMaliitKeyboard "maliit-keyboard"} &
          maliit_pid=$!
          applied_state=-1
          ${pkgs.uutils-coreutils-noprefix}/bin/sleep 0.1
        fi
        current_state=$(current_keyboard_state)
        if [ "$current_state" -ne "$applied_state" ] && set_virtual_keyboard "$current_state"; then
          applied_state=$current_state
        fi
        ${pkgs.uutils-coreutils-noprefix}/bin/sleep 0.5
      done

      stop_maliit
    done
  '';

  isKde = config.features.desktop.wm == "kde";
in
{
  config = lib.mkIf config.features.desktop.enable {
    services = {
      xserver.xkb = {
        layout = config.locale.keyboard;
        variant = "";
      };
      displayManager = {
        sddm = {
          enable = true;
          theme = sddmThemeName;
          wayland = {
            enable = true;
            compositor = "kwin";
          };
          settings = {
            General.GreeterEnvironment = sddmGreeterEnvironment;
            Theme = {
              CursorTheme = cursorTheme;
              CursorSize = cursorSize;
            };
          };
        };
        autoLogin = lib.mkIf (config.features.desktop.login == "autologin") {
          enable = true;
          user = config.user.name;
        };
        defaultSession = lib.mkDefault (if isKde then "plasma" else "hyprland-uwsm");
      };
    };

    systemd = {
      tmpfiles.rules = [
        "r /var/lib/sddm/.config/kwinoutputconfig.json - - - - -"
        "L+ /var/lib/sddm/.config/kwinrc - - - - ${sddmKwinrc}"
      ];
      services = {
        sddm-display-config = lib.mkIf shouldManageSddmLayout {
          description = "Configure SDDM monitor layout";
          before = [ "display-manager.service" ];
          wantedBy = [ "display-manager.service" ];
          serviceConfig = {
            Type = "oneshot";
            ExecStart = configureSddmDisplays;
          };
        };

        sddm-apply-display-config = lib.mkIf shouldApplySddmLayout {
          description = "Apply SDDM monitor layout after KWin starts";
          after = [ "display-manager.service" ];
          wantedBy = [ "display-manager.service" ];
          partOf = [ "display-manager.service" ];
          serviceConfig = {
            Type = "oneshot";
            User = "sddm";
            ExecStart = applySddmDisplayConfig;
          };
        };

        sddm-osk = {
          description = "Manage the SDDM on-screen keyboard";
          after = [ "display-manager.service" ];
          wantedBy = [ "display-manager.service" ];
          partOf = [ "display-manager.service" ];
          startLimitIntervalSec = 30;
          startLimitBurst = 5;
          serviceConfig = {
            Type = "simple";
            User = "sddm";
            ExecStart = sddmOsk;
            TimeoutStopSec = 3;
            Restart = "always";
            RestartSec = 1;
          };
        };

        sddm-deploy-colors = lib.mkIf config.features.gaming.steamMachine.enable {
          description = "Deploy Catppuccin color scheme for SDDM login screen";
          after = [ "var-lib-sddm.mount" ];
          before = [ "display-manager.service" ];
          wantedBy = [ "display-manager.service" ];
          serviceConfig = {
            Type = "oneshot";
            ExecStart = "${deploySddmColors} ${catppuccinColorsFile} ${colorSchemeId} ${sddmKdeglobals}";
          };
        };
      };
      paths.sddm-apply-display-config-watch = lib.mkIf shouldApplySddmLayout {
        description = "Reapply the SDDM monitor layout when a greeter Wayland socket appears";
        wantedBy = [ "display-manager.service" ];
        partOf = [ "display-manager.service" ];
        pathConfig = {
          PathChanged = "/run/user/${builtins.toString config.users.users.sddm.uid}";
          Unit = "sddm-apply-display-config.service";
        };
      };
    };

    catppuccin.sddm = {
      enable = true;
      font = uiFont;
      fontSize = "12";
      background = blurredWallpaper;
      loginBackground = true;
      userIcon = true;
      clockEnabled = false;
    };

    environment.systemPackages = [
      config.theme.cursor.package
    ];
  };
}
