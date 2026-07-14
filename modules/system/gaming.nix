# Gaming Configuration
#
# Installed:
# - Steam + Proton-GE     — gaming platform with enhanced Windows compatibility
# - Gamemode              — CPU governor + realtime scheduling when a game runs
# - Gamescope             — Wayland compositor for gaming (frame limiting, upscaling)
# - Steam Gamescope session (optional) — console-like Steam session for Steam Machine use
# - MangoHud              — in-game FPS/GPU/CPU overlay
# - ProtonUp-Qt           — GUI to manage Proton-GE versions
# - Steam Controller wake — allow the Valve wireless receiver to wake from standby
#
# VA-API drivers are configured in hardware.nix and apply to all desktop systems with a GPU,
# independent of gaming. gaming.nix only adds 32-bit libs (AMD) and diagnostic tools.

{
  pkgs,
  lib,
  config,
  ...
}:

let
  cfg = config.features.gaming;
  steamMachineCfg = cfg.steamMachine;

  desktopSession = if config.features.desktop.wm == "kde" then "plasma" else "hyprland-uwsm";

  # Desktop compositors distinguish vrr=1 (always) from vrr=2 (fullscreen/automatic).
  # Steam Machine mode is a dedicated fullscreen gamescope session, so any non-zero
  # monitor VRR mode means adaptive sync should be enabled there.
  displayHelpers = import ../lib/displays.nix { inherit lib; };
  steamMachineVrr =
    displayHelpers.hasVRR config.displays.monitors || config.displays.defaults.vrr != 0;
  hasHdrDisplay = displayHelpers.hasHDR config.displays.monitors || config.displays.defaults.hdr;

  steamMachineEnv = {
    SDL_VIDEO_MINIMIZE_ON_FOCUS_LOSS = "0";
    HOMETEST_DESKTOP = "1";
    HOMETEST_DESKTOP_SESSION = desktopSession;
    STEAM_ALLOW_DRIVE_ADOPT = "0";
    STEAM_ALLOW_DRIVE_UNMOUNT = "1";
    STEAM_ENABLE_VOLUME_HANDLER = "1";
    STEAM_GAMESCOPE_DYNAMIC_FPSLIMITER = "1";
    SRT_URLOPEN_PREFER_STEAM = "1";
    STEAM_DISABLE_AUDIO_DEVICE_SWITCHING = "1";
    STEAM_MULTIPLE_XWAYLANDS = "1";
    STEAM_GAMESCOPE_HAS_TEARING_SUPPORT = "1";
    STEAM_GAMESCOPE_NIS_SUPPORTED = "1";
    STEAM_GAMESCOPE_TEARING_SUPPORTED = "1";
    STEAM_GAMESCOPE_FANCY_SCALING_SUPPORT = "1";
    STEAM_DISABLE_MANGOAPP_ATOM_WORKAROUND = "1";
  }
  // lib.optionalAttrs steamMachineVrr {
    STEAM_GAMESCOPE_DYNAMIC_REFRESH_IN_STEAM_SUPPORTED = "1";
    STEAM_GAMESCOPE_VRR_SUPPORTED = "1";
  }
  // lib.optionalAttrs hasHdrDisplay {
    STEAM_GAMESCOPE_HDR_SUPPORTED = "1";
  };

  sessionSelect = pkgs.writeShellScriptBin "steamos-session-select" ''
    set -eu

    target="''${1:-desktop}"
    case "$target" in
      desktop|switch-to-desktop|plasma|hyprland|hyprland-uwsm|kde|gamescope|gamescope-wayland|steam|gaming|return-to-gaming-mode)
        ;;
      *)
        echo "steamos-session-select: unsupported target '$target', ending current session anyway" >&2
        ;;
    esac

    exit_file="''${STEAM_MACHINE_SESSION_EXIT_FILE:-''${XDG_RUNTIME_DIR:-/tmp}/steam-machine-session-exit}"
    mkdir -p "$(${pkgs.coreutils}/bin/dirname "$exit_file")"
    : > "$exit_file"

    ${pkgs.systemd}/bin/systemd-run --user --collect --on-active=1s \
      ${pkgs.runtimeShell} -c '${pkgs.procps}/bin/pkill -TERM -x steam || true; ${pkgs.procps}/bin/pkill -TERM -x steamwebhelper || true; sleep 5; ${pkgs.procps}/bin/pkill -TERM -x gamescope || true' >/dev/null
  '';

  steamosctl = pkgs.writeShellScriptBin "steamosctl" ''
    set -eu

    command="''${1:-}"
    case "$command" in
      set-default-desktop-session)
        # SteamOS uses this to tell steamos-manager which desktop to launch.
        # Our lightweight implementation returns to SDDM instead.
        exit 0
        ;;
      switch-to-desktop|desktop|switch-to-gaming-mode|gaming)
        exec ${sessionSelect}/bin/steamos-session-select "$command"
        ;;
      *)
        echo "steamosctl: unsupported command '$command'" >&2
        exit 0
        ;;
    esac
  '';

  steamMachineTools = pkgs.symlinkJoin {
    name = "steam-machine-session-tools";
    paths = [
      sessionSelect
      steamosctl
    ];
  };

  steamGamescopeSession =
    let
      exports = lib.mapAttrsToList (
        name: value: "export ${name}=${lib.escapeShellArg value}"
      ) steamMachineEnv;
      primaryOutput = displayHelpers.primaryName config.displays.monitors;
      gamescopeArgList = [
        "--backend"
        "drm"
        "--xwayland-count"
        "2"
        "--force-windows-fullscreen"
      ]
      ++ lib.optionals steamMachineVrr [
        "--adaptive-sync"
      ]
      ++ lib.optionals (primaryOutput != "") [
        "--prefer-output"
        primaryOutput
      ]
      ++ lib.optionals hasHdrDisplay [
        "--hdr-enabled"
      ];
      gamescopeArgs = lib.escapeShellArgs gamescopeArgList;
      steamArgs = lib.escapeShellArgs [
        "-steamos3"
        "-gamepadui"
        "-pipewire-dmabuf"
      ];
      steamStartupDelay = lib.optionalString hasHdrDisplay ''
        # Let Gamescope finish applying HDR on the DRM output before Steam
        # initializes its client-side HDR/color pipeline. Without this, Steam can
        # start washed out until HDR is toggled off/on in Game Mode.
        ${pkgs.coreutils}/bin/sleep 2
      '';
      steamGamescope = pkgs.writeShellScriptBin "steam-gamescope" ''
        set -eu

        ${lib.concatStringsSep "\n" exports}

        if [ -z "''${XDG_RUNTIME_DIR:-}" ]; then
          echo "steam-gamescope: XDG_RUNTIME_DIR is not set" >&2
          exit 1
        fi

        export XDG_SESSION_TYPE=x11
        ${pkgs.dbus}/bin/dbus-update-activation-environment --systemd \
          DESKTOP_SESSION XDG_CURRENT_DESKTOP XDG_SESSION_DESKTOP XDG_SESSION_TYPE XDG_RUNTIME_DIR || true

        session_dir="$(${pkgs.coreutils}/bin/mktemp -p "$XDG_RUNTIME_DIR" -d -t steam-machine.XXXXXXX)"
        startup_socket="$session_dir/startup.socket"
        stats_pipe="$session_dir/stats.pipe"
        ${pkgs.coreutils}/bin/mkfifo "$startup_socket" "$stats_pipe"

        exit_file="''${XDG_RUNTIME_DIR:-/tmp}/steam-machine-session-exit"
        export STEAM_MACHINE_SESSION_EXIT_FILE="$exit_file"
        rm -f "$exit_file"

        export GAMESCOPE_MODE_SAVE_FILE="''${XDG_CONFIG_HOME:-$HOME/.config}/gamescope/modes.cfg"
        export GAMESCOPE_PATCHED_EDID_FILE="''${XDG_CONFIG_HOME:-$HOME/.config}/gamescope/edid.bin"
        export GAMESCOPE_LIMITER_FILE="$session_dir/limiter"
        export GAMESCOPE_STATS="$stats_pipe"
        export ENABLE_GAMESCOPE_WSI=1

        mkdir -p "$(${pkgs.coreutils}/bin/dirname "$GAMESCOPE_MODE_SAVE_FILE")"
        touch "$GAMESCOPE_MODE_SAVE_FILE"
        touch "$GAMESCOPE_PATCHED_EDID_FILE"
        touch "$GAMESCOPE_LIMITER_FILE"

        ${pkgs.coreutils}/bin/cat "$stats_pipe" >/dev/null &
        stats_pid=$!

        cleanup() {
          ${pkgs.procps}/bin/pkill -TERM -P "$$" || true
          [ -n "''${gamescope_pid:-}" ] && kill "$gamescope_pid" 2>/dev/null || true
          [ -n "''${stats_pid:-}" ] && kill "$stats_pid" 2>/dev/null || true
          rm -f "$exit_file"
          rm -rf "$session_dir"
        }
        trap cleanup EXIT HUP INT TERM

        gamescope_bin=/run/wrappers/bin/gamescope
        [ -x "$gamescope_bin" ] || gamescope_bin=${pkgs.gamescope}/bin/gamescope

        "$gamescope_bin" --steam ${gamescopeArgs} \
          --generate-drm-mode fixed \
          --default-touch-mode 4 \
          --hide-cursor-delay 3000 \
          -e -R "$startup_socket" -T "$stats_pipe" &
        gamescope_pid=$!

        if read -r -t 10 response_x_display response_wl_display <> "$startup_socket"; then
          export DISPLAY="$response_x_display"
          export GAMESCOPE_WAYLAND_DISPLAY="$response_wl_display"
          export WAYLAND_DISPLAY="$response_wl_display"
          env > "$XDG_RUNTIME_DIR/gamescope-environment"
        else
          echo "steam-gamescope: gamescope did not report startup displays" >&2
        fi

        ${steamStartupDelay}

        ${config.programs.steam.package}/bin/steam ${steamArgs}
        status=$?

        kill "$gamescope_pid" 2>/dev/null || true
        wait "$gamescope_pid" 2>/dev/null || true
        exit "$status"
      '';
    in
    (pkgs.writeTextDir "share/wayland-sessions/steam.desktop" ''
      [Desktop Entry]
      Name=Steam
      Comment=A digital distribution platform
      Exec=${steamGamescope}/bin/steam-gamescope
      Type=Application
    '').overrideAttrs
      (_: {
        passthru.providedSessions = [ "steam" ];
      });
in
{
  options.features.gaming = {
    enable = (lib.mkEnableOption "gaming support (Steam, Gamemode, Gamescope)") // {
      default = true;
    };
    steamMachine = {
      enable = lib.mkEnableOption "Steam Machine mode with a selectable Steam session in SDDM";
    };
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [

      #---------------------------
      # Base gaming config
      #---------------------------
      {
        programs = {
          steam = {
            enable = true;
            # Translate Steam Input's desktop mouse/keyboard events to uinput on Wayland.
            extest.enable = true;
            # Open UDP 27031-27036 + TCP 27036-27037 for Steam Remote Play
            remotePlay.openFirewall = true;
            # Proton-GE: better compatibility than stock Proton for many games
            extraCompatPackages = [ pkgs.proton-ge-bin ];
          };

          gamemode = {
            enable = true;
            settings = {
              general = {
                # Raise game process priority (nice -10 = significantly more CPU time)
                renice = 10;
                # Give realtime scheduling to the game when the system can handle it
                softrealtime = "auto";
              };
            };
          };

          gamescope.enable = lib.mkIf steamMachineCfg.enable true;
        };

        environment.systemPackages =
          with pkgs;
          [
            gamescope
            mangohud # in-game overlay: FPS, GPU/CPU load, temps, VRAM
            protonup-qt # GUI to install/manage Proton-GE versions
          ]
          ++ lib.optional steamMachineCfg.enable steamMachineTools;

        security.wrappers.gamescope = lib.mkIf steamMachineCfg.enable {
          owner = "root";
          group = "root";
          source = "${pkgs.gamescope}/bin/gamescope";
          capabilities = "cap_sys_nice+pie";
        };

        hardware.graphics = lib.mkIf steamMachineCfg.enable {
          extraPackages = [ pkgs.gamescope-wsi ];
          extraPackages32 = [ pkgs.pkgsi686Linux.gamescope-wsi ];
        };

        services.displayManager.sessionPackages = lib.mkIf steamMachineCfg.enable [
          steamGamescopeSession
        ];

        services.udev.extraRules = ''
          # Steam Controller Wireless Receiver: allow the controller power button to wake the PC.
          ACTION=="add", SUBSYSTEM=="usb", ATTR{idVendor}=="28de", ATTR{idProduct}=="1142", ATTR{power/wakeup}="enabled"
          ACTION=="add", SUBSYSTEM=="usb", ATTR{idVendor}=="28de", ATTR{idProduct}=="1304", ATTR{power/wakeup}="enabled"
        '';

        boot.kernel.sysctl = {
          # Reduce swap pressure during gaming (zram is fast, but still adds latency)
          "vm.swappiness" = 10;
          # Network buffer tuning for Steam Remote Play over LAN
          # CachyOS kernel has BBR support; fq qdisc pairs with it for best throughput.
          "net.core.rmem_max" = 134217728; # 128 MB receive buffer
          "net.core.wmem_max" = 134217728; # 128 MB send buffer
          "net.core.default_qdisc" = "fq";
          "net.ipv4.tcp_congestion_control" = "bbr";
        };
      }

      #---------------------------
      # AMD GPU: 32-bit graphics for Steam Remote Play
      #---------------------------
      # enable32Bit: Steam's streaming encoder is 32-bit and requires 32-bit GPU drivers.
      # VA-API drivers and LIBVA_DRIVER_NAME are set in hardware.nix for all GPU users.
      (lib.mkIf (config.features.hardware.gpu == "amd") {
        environment.systemPackages = [ pkgs.libva-utils ]; # vainfo: verify VA-API works
        hardware.graphics.enable32Bit = true;
      })

      #---------------------------
      # Intel GPU: VA-API tools for gaming/streaming
      #---------------------------
      # Drivers and LIBVA_DRIVER_NAME are set in hardware.nix.
      (lib.mkIf (config.features.hardware.gpu == "intel") {
        environment.systemPackages = [ pkgs.libva-utils ];
      })

    ]
  );

}
