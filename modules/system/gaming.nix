# Gaming Configuration
#
# Installed:
# - Steam + Proton-GE     — gaming platform with enhanced Windows compatibility
# - Gamemode              — CPU governor + realtime scheduling when a game runs
# - Gamescope             — Wayland compositor for gaming (frame limiting, upscaling)
# - MangoHud              — in-game FPS/GPU/CPU overlay
# - ProtonUp-Qt           — GUI to manage Proton-GE versions
#
# features.gaming.gpu:
#   "amd"   — VA-API via Mesa radeonsi (RDNA2+)
#   "intel" — VA-API via intel-media-driver (iHD, Gen 9+)
#
# features.gaming.gamescope.enable:
#   Registers a standalone "Steam" Wayland session in SDDM (Big Picture Mode).
#   Still allows booting to the normal desktop — both sessions appear at login.
#
# features.gaming.gamescope.sessionSwitcher.enable:
#   Installs steamos-session-select for Steam Deck-style switching between
#   gamescope and desktop. Forces features.desktop.autoLogin.enable.

{ pkgs, lib, config, ... }:

let
  cfg = config.features.gaming;
in
{
  options.features.gaming = {
    enable = (lib.mkEnableOption "gaming support (Steam, Gamemode, Gamescope)") // { default = true; };
    gpu = lib.mkOption {
      type = lib.types.nullOr (lib.types.enum [ "amd" "intel" ]);
      default = null;
      description = "GPU vendor — enables VA-API hardware encoding for Steam Remote Play";
    };
    gamescope = {
      enable = lib.mkEnableOption "standalone Steam Wayland session in SDDM (Big Picture Mode)";
      args = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "Extra arguments passed to gamescope in the Steam session";
        example = [ "-W 1920" "-H 1080" "-r 60" "--hdr-enabled" ];
      };
      sessionSwitcher = {
        enable = lib.mkEnableOption "steamos-session-select — Steam Deck-style session switching (forces autoLogin)";
      };
    };
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [

    #---------------------------
    # Base gaming config
    #---------------------------
    {
      programs.steam = {
        enable = true;
        # Open UDP 27031-27036 + TCP 27036-27037 for Steam Remote Play
        remotePlay.openFirewall = true;
        # Proton-GE: better compatibility than stock Proton for many games
        extraCompatPackages = [ pkgs.proton-ge-bin ];
      };

      programs.gamemode = {
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

      environment.systemPackages = with pkgs; [
        gamescope
        mangohud   # in-game overlay: FPS, GPU/CPU load, temps, VRAM
        protonup-qt # GUI to install/manage Proton-GE versions
      ];

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
    # AMD GPU: VA-API hardware encoding
    #---------------------------
    # Mesa radeonsi provides VAAPI via VCN encoder (RDNA2+).
    # Without this, Steam falls back to software encoding → stream freezes.
    (lib.mkIf (cfg.gpu == "amd") {
      environment.systemPackages = [ pkgs.libva-utils ]; # vainfo: verify encoding works
      hardware.graphics.extraPackages = [ pkgs.libvdpau-va-gl ];
      # Wayland sessions sometimes fail to auto-detect the VA-API driver
      environment.sessionVariables.LIBVA_DRIVER_NAME = "radeonsi";
    })

    #---------------------------
    # Intel GPU: VA-API hardware encoding
    #---------------------------
    # intel-media-driver (iHD) provides VAAPI for Gen 9+ (Broadwell and newer).
    (lib.mkIf (cfg.gpu == "intel") {
      environment.systemPackages = [ pkgs.libva-utils ];
      hardware.graphics.extraPackages = with pkgs; [
        intel-media-driver # iHD VA-API driver
        libvdpau-va-gl
      ];
      environment.sessionVariables.LIBVA_DRIVER_NAME = "iHD";
    })

    #---------------------------
    # Gamescope Session
    #---------------------------
    # Registers a "Steam" Wayland session in SDDM alongside the normal desktop.
    # Disabled automatically when features.gaming.enable = false.
    (lib.mkIf cfg.gamescope.enable {
      programs.steam.gamescopeSession = {
        enable = true;
        inherit (cfg.gamescope) args;
        # SteamOS=1 tells Steam it's running in a gamescope kiosk session.
        # Without this Steam doesn't call steamos-session-select on "Switch to Desktop".
        env.SteamOS = "1";
      };
    })

    #---------------------------
    # Session Switcher
    #---------------------------
    # WHY systemd service + polkit: auto-login uses [Autologin] Session= from
    # /etc/sddm.conf.d/ (NixOS-managed, root-only). state.conf only affects
    # greeter pre-selection. A setuid shell script doesn't work — bash drops
    # EUID when EUID≠UID. Instead: a systemd oneshot service runs as root and
    # does the actual work; a polkit rule lets sddm-session group members start
    # it without a password. The desired session is passed via /run/sddm-next-session.
    (lib.mkIf cfg.gamescope.sessionSwitcher.enable {
      features.desktop.autoLogin.enable = lib.mkForce true;
      services.displayManager.defaultSession = lib.mkForce "steam";

      users.groups.sddm-session = { };
      users.users.${config.user.name}.extraGroups = [ "sddm-session" ];

      # /run/sddm-next-session: user writes target session name here
      systemd.tmpfiles.rules = [
        "f /run/sddm-next-session 0664 root sddm-session -"
      ];

      # Runs as root: reads /run/sddm-next-session, writes SDDM override, restarts DM
      systemd.services.sddm-session-switch = {
        description = "Switch SDDM autologin session";
        serviceConfig = {
          Type = "oneshot";
          ExecStart = pkgs.writeShellScript "sddm-session-switch-exec" ''
            SESSION=$(cat /run/sddm-next-session 2>/dev/null)
            case "$SESSION" in
              ${if config.features.desktop.wm == "kde" then "plasma" else "hyprland-uwsm"}|steam) ;;
              *) echo "Invalid session: $SESSION" >&2; exit 1 ;;
            esac
            printf '[Autologin]\nSession=%s.desktop\n' "$SESSION" \
              > /etc/sddm.conf.d/99-session-switch.conf
            exec ${pkgs.systemd}/bin/systemctl restart display-manager.service
          '';
        };
      };

      # Allow sddm-session group to start the switch service without a password
      security.polkit.extraConfig = ''
        polkit.addRule(function(action, subject) {
          if (action.id === "org.freedesktop.systemd1.manage-units" &&
              action.lookup("unit") === "sddm-session-switch.service" &&
              action.lookup("verb") === "start" &&
              subject.isInGroup("sddm-session")) {
            return polkit.Result.YES;
          }
        });
      '';

      environment.systemPackages = [
        (pkgs.writeShellScriptBin "steamos-session-select" ''
          set -euo pipefail
          case "''${1:-desktop}" in
            desktop)         SESSION="${if config.features.desktop.wm == "kde" then "plasma" else "hyprland-uwsm"}" ;;
            gamescope|steam) SESSION="steam" ;;
            *) echo "Usage: steamos-session-select [desktop|gamescope]" >&2; exit 1 ;;
          esac
          echo "$SESSION" > /run/sddm-next-session
          # setsid: systemctl start must happen after this script returns,
          # otherwise Steam is killed mid-call and the switch appears to hang.
          setsid sh -c 'sleep 0.5; systemctl start sddm-session-switch.service' &
        '')
      ];
    })

  ]);
}
