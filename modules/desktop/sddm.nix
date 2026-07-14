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

  primaryScale = if monitors != [ ] then (builtins.head monitors).scale else config.theme.scale;
  scaledDpi = builtins.floor (96 * primaryScale);
  scaledCursorSize = builtins.floor (cursorSize * primaryScale);

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
  monitorPriorities = lib.listToAttrs (lib.imap0 (i: m: lib.nameValuePair m.name i) monitors);
  kscreenRotation =
    rot:
    {
      "normal" = "normal";
      "90" = "right";
      "180" = "inverted";
      "270" = "left";
    }
    .${rot};
  sddmKscreenArgs = lib.concatMapStringsSep " " (
    m:
    lib.concatStringsSep " " (
      [
        "output.${m.name}.scale.${toString m.scale}"
        "output.${m.name}.mode.${toString m.width}x${toString m.height}@${toString m.refreshRate}"
        "output.${m.name}.position.${toString m.x},${toString m.y}"
        "output.${m.name}.rotation.${kscreenRotation m.rotation}"
      ]
      ++ lib.optional (m.vrr == 0) "output.${m.name}.vrrpolicy.never"
      ++ lib.optional (m.vrr == 1) "output.${m.name}.vrrpolicy.always"
      ++ lib.optional (m.vrr == 2) "output.${m.name}.vrrpolicy.automatic"
      ++ lib.optionals m.hdr [
        "output.${m.name}.hdr.enable"
        "output.${m.name}.wcg.enable"
        "output.${m.name}.sdr-brightness.${toString m.hdrSdrMaxLuminance}"
      ]
    )
  ) monitors;

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
          highDynamicRange = m.hdr;
          wideColorGamut = m.hdr;
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
  shouldManageSddmLayout = monitors != [ ] && (monitorsWithEdid == [ ] || monitorsWithEdid == monitors);
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
    set -eu

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

    for attempt in $(${pkgs.coreutils}/bin/seq 1 50); do
      for socket in "$XDG_RUNTIME_DIR"/wayland-*; do
        [ -S "$socket" ] || continue
        case "$socket" in
          *.lock) continue ;;
        esac

        export WAYLAND_DISPLAY=$(${pkgs.coreutils}/bin/basename "$socket")
        ${pkgs.kdePackages.libkscreen}/bin/kscreen-doctor ${sddmKscreenArgs} && exit 0
      done

      ${pkgs.coreutils}/bin/sleep 0.1
    done

    echo "apply-sddm-display-config: no usable SDDM Wayland socket found" >&2
    exit 1
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
          wayland.enable = true;
          wayland.compositor = "kwin";
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
          serviceConfig = {
            Type = "oneshot";
            User = "sddm";
            ExecStart = applySddmDisplayConfig;
          };
        };

      };

      tmpfiles.rules = [
        "d /var/lib/sddm/.config 0755 sddm sddm -"
        "r /var/lib/sddm/.config/kwinoutputconfig.json - - - - -"
      ];
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
