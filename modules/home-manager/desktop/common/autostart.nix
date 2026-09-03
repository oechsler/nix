# Autostart Configuration (Common)
#
# This module defines applications that start automatically on login.
#
# Features:
# - Cross-WM support (Hyprland and KDE)
# - Feature-flag aware (only starts apps if features enabled)
#
# Window-manager-specific implementation:
# - Hyprland: Converts the list into systemd user services in hyprland/default.nix
# - KDE: Converts the list into XDG autostart files in kde/autostart.nix
#
# The application list is deliberately shared. Only the lifecycle mechanism
# differs: Hyprland owns explicit user units, while KDE consumes XDG entries.
#
# Default autostart apps:
# - Proton Pass - Password manager
# - Vesktop - Discord client (minimized)
# - Nextcloud - Cloud sync (XDG autostart on both WMs)
# - Pika Backup Monitor (if features.apps.enable)
# - Trayscale - Tailscale tray (if features.tailscale.enable)
# - Steam (if features.gaming.enable)
#
# Configuration:
#   autostart.apps = [ { name = "App"; exec = "command"; } ];

{
  config,
  lib,
  pkgs,
  features,
  displays,
  ...
}:

let
  isKde = features.desktop.wm == "kde";
  displayHelpers = import ../../../lib/displays.nix { inherit lib; };
  hasHDR = displayHelpers.hasDesktopHDR displays.monitors || displays.defaults.hdr == 2;
  chromium = import ../../../lib/chromium.nix { inherit pkgs; };
  protonPassPackage = pkgs.proton-pass.overrideAttrs (old: {
    postFixup = (old.postFixup or "") + ''
      substituteInPlace "$out/bin/proton-pass" \
        --replace-fail "${lib.getExe pkgs.electron}" "${lib.getExe pkgs.electron_42}"
    '';
  });
  protonPass = chromium.wrapHdrSdrApp {
    package = protonPassPackage;
    binary = "proton-pass";
    enable = hasHDR;
    name = "proton-pass-electron-hdr-sdr";
  };
  mumbleEnabled = features.apps.enable && features.apps.mumble.enable;
  mumbleDesktopFile =
    lib.replaceStrings [ "Exec=mumble %u" ] [ "Exec=${config.programs.mumble.launcher} %u" ]
      (builtins.readFile "${pkgs.mumble}/share/applications/info.mumble.Mumble.desktop");

  desktopSteamCondition = pkgs.writeShellScript "steam-desktop-condition" ''
    set -eu

    pid_file="''${XDG_RUNTIME_DIR:-/tmp}/steam-gamescope-pid"
    if [ -r "$pid_file" ] && read -r steam_pid < "$pid_file" \
      && kill -0 "$steam_pid" 2>/dev/null; then
      exit 1
    fi
    exit 0
  '';
  trayscaleStart = pkgs.writeShellScript "trayscale-start" ''
    set -eu
    # Tailscale may need a few seconds after the graphical session starts.
    ${pkgs.coreutils}/bin/sleep 10
    exec ${pkgs.trayscale}/bin/trayscale --hide-window
  '';
  steamStart = pkgs.writeShellScript "steam-start" ''
    set -eu
    ${pkgs.coreutils}/bin/sleep 20
    exec ${pkgs.steam}/bin/steam -silent
  '';
in
{
  #===========================
  # Options
  #===========================

  options.autostart.apps = lib.mkOption {
    type = lib.types.listOf (
      lib.types.submodule {
        options = {
          name = lib.mkOption {
            type = lib.types.str;
            description = "Human-readable application name";
          };
          exec = lib.mkOption {
            type = lib.types.str;
            description = "Command to execute";
          };
        };
      }
    );
    default = [ ];
    description = "Applications to start on login (works on both Hyprland and KDE)";
  };

  #===========================
  # Configuration
  #===========================

  config = lib.mkMerge [
    {

      #---------------------------
      # Default Autostart Apps
      #---------------------------
      autostart.apps =
        lib.optionals features.apps.enable [
          {
            name = "Proton Pass";
            exec = "${protonPass}/bin/proton-pass --hidden";
          }
          {
            name = "Vesktop";
            exec = "${config.programs.vesktop.package}/bin/vesktop --start-minimized";
          }
        ]
        ++ lib.optionals mumbleEnabled [
          {
            name = "Mumble";
            exec = if isKde then config.programs.mumble.launcher else config.programs.mumble.command;
          }
        ]
        # Hyprland starts Steam through the dedicated service below. Steam gets
        # a longer delay because gamescope and Steam Input need the fully
        # initialized Wayland/uinput session before they are started.
        ++ lib.optionals (features.gaming.enable && isKde) [
          {
            name = "Steam";
            exec = "${pkgs.steam}/bin/steam -silent";
          }
        ];

      home.file = lib.mkIf mumbleEnabled {
        ${".local/share/applications/info.mumble.Mumble.desktop"} = {
          text = mumbleDesktopFile;
        };
      };

      #---------------------------
      # Nextcloud XDG Autostart (declarative)
      #---------------------------
      # Nextcloud creates ~/.config/autostart/Nextcloud.desktop at runtime — not
      # declarative. We own the file so it exists on fresh installs and the
      # systemd-xdg-autostart-generator picks it up on both Hyprland and KDE.
      # Pika Backup: the package ships its own autostart .desktop, no entry needed.
      xdg.configFile."autostart/Nextcloud.desktop" = lib.mkIf features.apps.nextcloud.enable {
        text = ''
          [Desktop Entry]
          Type=Application
          Name=Nextcloud
           Exec=${pkgs.nextcloud-client}/bin/nextcloud --background
        '';
      };

    }

    #---------------------------
    # Trayscale systemd service
    # (reliable: waits for graphical-session.target, restarts on failure)
    #---------------------------
    (lib.mkIf features.tailscale.enable {
      systemd.user.services.trayscale = {
        Unit = {
          Description = "Trayscale - Tailscale tray applet";
          After = [
            "graphical-session.target"
            "waybar.service"
          ];
          PartOf = [ "graphical-session.target" ];
        };
        Service = {
          # Waybar provides the StatusNotifierWatcher; wait for it before
          # registering the tray item.
          ExecStart = trayscaleStart;
          Restart = "on-failure";
          RestartSec = 3;
        };
        Install.WantedBy = [ "graphical-session.target" ];
      };
    })

    #---------------------------
    # Steam systemd service (Hyprland)
    #---------------------------
    (lib.mkIf (features.gaming.enable && !isKde) {
      systemd.user.services.steam = {
        Unit = {
          Description = "Steam - gaming platform";
          After = [ "graphical-session.target" ];
          PartOf = [ "graphical-session.target" ];
        };
        Service = {
          ExecStart = steamStart;
          ExecCondition = "${desktopSteamCondition}";
          Environment = "PATH=/etc/profiles/per-user/${config.home.username}/bin:/run/current-system/sw/bin";
          Type = "exec";
          Restart = "on-failure";
          RestartPreventExitStatus = 1;
          RestartSec = 3;
          TimeoutStopSec = 10;
        };
        Install.WantedBy = [ "graphical-session.target" ];
      };
    })

  ]; # end mkMerge
}
