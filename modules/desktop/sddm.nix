# SDDM Display Manager Configuration
#
# This module configures SDDM (Simple Desktop Display Manager) as the login screen.
#
# Features:
# - Wayland session support
# - Catppuccin theming (matches desktop theme)
# - KWin Wayland greeter with monitor fallback
# - DPI scaling for Hyprland (calculated from primary monitor)
# - Cursor theme and size (scaled for HiDPI)
# - Login mode (features.desktop.login: "greeter" shows login, "autologin" skips it)
# - Dynamic on-screen keyboard: maliit-keyboard via zwp_input_method_v1 protocol
#   when no physical keyboard is detected at boot
#
# Why SDDM:
# - Native Wayland support
# - Works with both Hyprland and KDE Plasma
# - Themeable with Catppuccin
#
# Multi-monitor setup:
# - Uses the configured layout only when all configured outputs have matching EDIDs
# - Falls back to SDDM/KWin auto-detection for unknown or partial monitor setups
#
# HiDPI handling:
# - KDE: Uses cursor size as-is
# - Hyprland: Scales cursor and DPI based on primary monitor scale
#
# Active when: features.desktop.enable = true

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
  uiFont = config.fonts.defaults.ui;

  capitalize = s: (lib.toUpper (builtins.substring 0 1 s)) + (builtins.substring 1 (builtins.stringLength s) s);
  colorSchemeId = "Catppuccin${capitalize config.theme.catppuccin.flavor}${capitalize config.theme.catppuccin.accent}";
  catppuccinColorsFile = "${pkgs.catppuccin-kde.override {
    flavour = [ config.theme.catppuccin.flavor ];
    accents = [ config.theme.catppuccin.accent ];
  }}/share/color-schemes/${colorSchemeId}.colors";
  sddmKdeglobals = pkgs.writeText "sddm-kdeglobals" ''
    [General]
    ColorScheme=${colorSchemeId}
  '';

  deploySddmColors = pkgs.writeShellScript "deploy-sddm-colors" ''
    set -eu
    colors_src="$1"
    colors_name="$2"
    kdeglobals_src="$3"

    mkdir -p /var/lib/sddm/.config
    mkdir -p /var/lib/sddm/.local/share/color-schemes
    ln -sf "$colors_src" "/var/lib/sddm/.local/share/color-schemes/$colors_name.colors"
    cp "$kdeglobals_src" /var/lib/sddm/.config/kdeglobals
    chown -R sddm:sddm /var/lib/sddm/.config /var/lib/sddm/.local/share
  '';
  sddmGreeterEnvironment = lib.concatStringsSep "," (
    [
      "QT_WAYLAND_SHELL_INTEGRATION=layer-shell"
    ]
    ++ lib.optionals (!isKde) [ "QT_FONT_DPI=${toString scaledDpi}" ]
    ++ [
      "XCURSOR_THEME=${cursorTheme}"
      "XCURSOR_SIZE=${toString (if isKde then cursorSize else scaledCursorSize)}"
    ]
  );

  displayHelpers = import ../lib/displays.nix { inherit lib; };
  primaryScale = displayHelpers.primaryScale config.theme.scale monitors;
  scaledDpi = builtins.floor (96 * primaryScale);
  scaledCursorSize = builtins.floor (cursorSize * primaryScale);
  kscreen = import ../lib/kscreen.nix { inherit lib; };

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
  configuredOutputEdids = lib.escapeShellArgs (map (m: "${m.name}:${m.edidHash}") monitorsWithEdid);
  configuredOutputEdidChecks = lib.optionalString (monitorsWithEdid != [ ]) ''
    for identity in ${configuredOutputEdids}; do
      output=''${identity%%:*}
      expected_edid=''${identity#*:}
      matched_edid=0

      for edid_file in /sys/class/drm/*-"$output"/edid; do
        status_file=''${edid_file%/edid}/status
        if [ -s "$edid_file" ] && [ -e "$status_file" ] && [ "$(cat "$status_file")" = connected ]; then
          actual_edid=$(${pkgs.coreutils}/bin/sha256sum "$edid_file" | ${pkgs.coreutils}/bin/cut -d' ' -f1)
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

    mkdir -p "$config_dir"
    chown sddm:sddm "$config_dir"
    chmod 0755 "$config_dir"

    all_connected=1
    for output in ${configuredOutputNames}; do
      connected=0
      for status_file in /sys/class/drm/*-"$output"/status; do
        if [ -e "$status_file" ] && [ "$(cat "$status_file")" = connected ]; then
          connected=1
        fi
      done

      if [ "$connected" -ne 1 ]; then
        all_connected=0
      fi
    done

    ${configuredOutputEdidChecks}

    if [ "$all_connected" -eq 1 ]; then
      install -o sddm -g sddm -m 0644 ${sddmDisplayConfigFile} "$config_file"
    else
      rm -f "$config_file"
    fi
  '';

  applySddmDisplayConfig = pkgs.writeShellScript "apply-sddm-display-config" ''
    set -eu

    sddm_uid=$(${pkgs.coreutils}/bin/id -u sddm)
    export XDG_RUNTIME_DIR=/run/user/$sddm_uid
    export DBUS_SESSION_BUS_ADDRESS=unix:path=$XDG_RUNTIME_DIR/bus

    echo "apply-sddm-display-config: waiting for sddm session bus (uid=$sddm_uid)" >&2
    bus_ready=0
    for attempt in $(${pkgs.coreutils}/bin/seq 1 600); do
      if [ -S "$XDG_RUNTIME_DIR/bus" ]; then
        bus_ready=1
        break
      fi
      ${pkgs.coreutils}/bin/sleep 0.1
    done
    if [ "$bus_ready" -ne 1 ]; then
      echo "apply-sddm-display-config: sddm session bus never appeared, giving up" >&2
      exit 0
    fi

    echo "apply-sddm-display-config: bus ready, waiting for KWin D-Bus…" >&2
    for attempt in $(${pkgs.coreutils}/bin/seq 1 300); do
      if ${pkgs.dbus}/bin/dbus-send --session \
        --dest=org.freedesktop.DBus --type=method_call --print-reply \
        /org/freedesktop/DBus org.freedesktop.DBus.ListNames \
        2>/dev/null | ${pkgs.gnugrep}/bin/grep -q org.kde.KWin; then
        break
      fi
      ${pkgs.coreutils}/bin/sleep 0.1
    done

    # kscreen-doctor (monitor layout)
    for socket in "$XDG_RUNTIME_DIR"/wayland-*; do
      [ -S "$socket" ] || continue
      case "$socket" in *.lock) continue ;; esac
      export WAYLAND_DISPLAY=$(${pkgs.coreutils}/bin/basename "$socket")
      ${pkgs.kdePackages.libkscreen}/bin/kscreen-doctor ${sddmKscreenArgs} && break
    done

    # Force virtual keyboard mode=2 (On) then activate
    ${pkgs.dbus}/bin/dbus-send --session \
      --dest=org.kde.KWin --type=method_call --print-reply \
      /VirtualKeyboard org.freedesktop.DBus.Properties.Set \
      string:"org.kde.kwin.VirtualKeyboard" string:"mode" variant:int32:2
    ${pkgs.dbus}/bin/dbus-send --session \
      --dest=org.kde.KWin --type=method_call --print-reply \
      /VirtualKeyboard org.kde.kwin.VirtualKeyboard.forceActivate

    echo "apply-sddm-display-config: done" >&2
  '';

  sddmThemeName = "catppuccin-${config.catppuccin.sddm.flavor}-${config.catppuccin.sddm.accent}";

  sddmKwin = pkgs.writeShellScript "sddm-kwin" ''
        set -eu

        export HOME=/var/lib/sddm
        export XDG_CONFIG_HOME=/var/lib/sddm/.config
        export XDG_DATA_HOME=/var/lib/sddm/.local/share
        export XDG_CURRENT_DESKTOP=KDE
        export KDE_FULL_SESSION=true

        enable_keyboard=0
        kwin_pid=""
        maliit_pid=""

        cleanup() {
            kill "$kwin_pid" 2>/dev/null || true
            kill "$maliit_pid" 2>/dev/null || true
            exit 1
        }
        trap cleanup INT TERM

${lib.optionalString config.features.gaming.steamMachine.enable ''
        # First pass: collect vendor IDs that have joystick/gamepad devices.
        # The Steam Controller in Lizard Mode exposes TWO separate evdev devices:
        #   - keyboard half:  ID_INPUT_KEYBOARD=1, no joystick
        #   - gamepad half:   ID_INPUT_JOYSTICK=1
        # A per-device check would miss the keyboard half, so we exclude by vendor.
        joystick_vendors=""
        for dev in /dev/input/event*; do
          [ -e "$dev" ] || continue
          props=$(${pkgs.systemd}/bin/udevadm info --query=property --name="$dev" 2>/dev/null) || continue
          ${pkgs.gnugrep}/bin/grep -qx 'ID_INPUT_JOYSTICK=1' <<< "$props" || continue
          vendor=$(${pkgs.gnugrep}/bin/grep '^ID_VENDOR_ID=' <<< "$props" | ${pkgs.coreutils}/bin/cut -d= -f2- || true)
          [ -n "$vendor" ] && joystick_vendors="$joystick_vendors $vendor"
        done

        # Second pass: find real keyboards (exclude joystick vendors + model heuristics)
        has_keyboard=0
        for dev in /dev/input/event*; do
          [ -e "$dev" ] || continue
          props=$(${pkgs.systemd}/bin/udevadm info --query=property --name="$dev" 2>/dev/null) || continue
          ${pkgs.gnugrep}/bin/grep -qx 'ID_INPUT_KEYBOARD=1' <<< "$props" || continue

          vendor=$(${pkgs.gnugrep}/bin/grep '^ID_VENDOR_ID=' <<< "$props" | ${pkgs.coreutils}/bin/cut -d= -f2- || true)
          for jv in $joystick_vendors; do
            [ "$vendor" = "$jv" ] && continue 2
          done

          model=$(${pkgs.gnugrep}/bin/grep '^ID_MODEL=' <<< "$props" | ${pkgs.coreutils}/bin/cut -d= -f2- || true)
          case "$model" in
            *Controller*|*Gamepad*|*Joystick*|*Steam*Controller*) continue ;;
          esac

          has_keyboard=1
          break
        done

        echo "sddm-kwin: has_keyboard=$has_keyboard joystick_vendors='$joystick_vendors'" >> /tmp/sddm-kwin.log
        if [ "$has_keyboard" -eq 0 ]; then
          enable_keyboard=1
          echo "sddm-kwin: enabling maliit-keyboard" >> /tmp/sddm-kwin.log

          # KWin reads kwinrc at startup for virtual keyboard settings.
          kwinrc_dir=/var/lib/sddm/.config
          mkdir -p "$kwinrc_dir"
          cat > "$kwinrc_dir"/kwinrc << 'EOF'
[VirtualKeyboard]
VirtualKeyboardEnabled=true
VirtualKeyboardMode=2
EOF
          chown -R sddm:sddm "$kwinrc_dir"
        fi
''}

        # Start KWin as the Wayland compositor.
        # Maliit-keyboard connects to it as an external Wayland client
        # via the zwp_input_method_v1 protocol.
        echo "sddm-kwin: starting kwin_wayland" >> /tmp/sddm-kwin.log
        ${lib.getExe' pkgs.kdePackages.kwin "kwin_wayland"} \
          --no-global-shortcuts \
          --no-kactivities \
          --locale1 \
          >> /tmp/kwin_wayland.log 2>&1 &
        kwin_pid=$!

        if [ "$enable_keyboard" -eq 1 ]; then
          export WAYLAND_DISPLAY="''${WAYLAND_DISPLAY:-wayland-0}"
          export XDG_RUNTIME_DIR="''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"

          # Wait for KWin to create the Wayland socket.
          for i in $(seq 1 50); do
            if [ -S "$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY" ]; then
              echo "sddm-kwin: Wayland socket ready after $i attempts" >> /tmp/sddm-kwin.log
              break
            fi
            sleep 0.05
          done

          echo "sddm-kwin: starting maliit-keyboard (WAYLAND_DISPLAY=$WAYLAND_DISPLAY)" >> /tmp/sddm-kwin.log
          ${lib.getExe' pkgs.maliit-keyboard "maliit-keyboard"} >> /tmp/maliit-keyboard.log 2>&1 &
          maliit_pid=$!
        fi

        wait $kwin_pid
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
            compositorCommand = toString sddmKwin;
          };
          extraPackages = [ pkgs.maliit-keyboard ];
          settings = {
            General.GreeterEnvironment = sddmGreeterEnvironment;
            Theme = {
              CursorTheme = cursorTheme;
              CursorSize = if isKde then cursorSize else scaledCursorSize;
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

    # SDDM uses kwin_wayland. Without EDID hashes, keep the configured layout
    # when all configured connectors are present. If EDID hashes are configured,
    # require all monitors to match exactly.
    systemd = {
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

        sddm-apply-display-config = lib.mkIf shouldManageSddmLayout {
          description = "Apply SDDM monitor layout after KWin starts";
          after = [ "display-manager.service" ];
          wantedBy = [ "display-manager.service" ];
          partOf = [ "display-manager.service" ];
          serviceConfig = {
            Type = "oneshot";
            User = "sddm";
            ExecStart = applySddmDisplayConfig;
            RemainAfterExit = true;
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

      tmpfiles.rules = [
        "r /var/lib/sddm/.config/kwinoutputconfig.json - - - - -"
      ];
    };

    # The on-screen keyboard is provided by maliit-keyboard via the
    # zwp_input_method_v1 Wayland protocol when sddmKwin detects no
    # physical keyboard. The Catppuccin SDDM theme is used as-is.
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
