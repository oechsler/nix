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

  desktopSession =
    if config.features.desktop.wm == "kde" then
      "plasma"
    else
      "hyprland-uwsm";

  steamMachineEnv = {
    SDL_VIDEO_MINIMIZE_ON_FOCUS_LOSS = "0";
    HOMETEST_DESKTOP = "1";
    HOMETEST_DESKTOP_SESSION = desktopSession;
    SRT_URLOPEN_PREFER_STEAM = "1";
    STEAM_DISABLE_AUDIO_DEVICE_SWITCHING = "1";
    STEAM_MULTIPLE_XWAYLANDS = "1";
    STEAM_GAMESCOPE_HAS_TEARING_SUPPORT = "1";
    STEAM_GAMESCOPE_NIS_SUPPORTED = "1";
    STEAM_GAMESCOPE_TEARING_SUPPORTED = "1";
    STEAM_GAMESCOPE_VRR_SUPPORTED = "1";
    STEAM_GAMESCOPE_FANCY_SCALING_SUPPORT = "1";
    STEAM_DISABLE_MANGOAPP_ATOM_WORKAROUND = "1";
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

    # Switching out of the Steam session is intentionally unsupported here.
    # Rebooting is the reliable escape hatch for this console-like session.
    exit 0
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
      exports = lib.mapAttrsToList (name: value: "export ${name}=${lib.escapeShellArg value}") steamMachineEnv;
      preferredOutputs = lib.concatStringsSep "," (map (m: m.name) config.displays.monitors);
      gamescopeArgList =
        [
          "--xwayland-count"
          "2"
          "--force-windows-fullscreen"
        ]
        ++ lib.optionals (preferredOutputs != "") [
          "--prefer-output"
          preferredOutputs
        ];
      gamescopeArgs = lib.escapeShellArgs gamescopeArgList;
      steamArgs = lib.escapeShellArgs [
        "-gamepadui"
        "-pipewire-dmabuf"
      ];
      steamGamescope = pkgs.writeShellScriptBin "steam-gamescope" ''
        set -eu

        ${lib.concatStringsSep "\n" exports}

        exec ${pkgs.gamescope}/bin/gamescope --steam ${gamescopeArgs} -- ${config.programs.steam.package}/bin/steam ${steamArgs}
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

        environment.systemPackages = with pkgs; [
          gamescope
          mangohud # in-game overlay: FPS, GPU/CPU load, temps, VRAM
          protonup-qt # GUI to install/manage Proton-GE versions
        ] ++ lib.optional steamMachineCfg.enable steamMachineTools;

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
