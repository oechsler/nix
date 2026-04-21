# Gaming Configuration
#
# Packages: Steam + Proton-GE, Gamemode, Gamescope, MangoHud, ProtonUp-Qt
#
# features.gaming.gpu:
#   "amd"   — VA-API via Mesa radeonsi (RDNA2+)
#   "intel" — VA-API via intel-media-driver (Gen 9+)
#
# features.gaming.gamescope.enable:
#   Registers a standalone "Steam" Wayland session in SDDM (Big Picture Mode).
#   gamescope.sessionSwitcher.enable installs steamos-session-select for
#   seamless switching between gamescope and desktop (forces autoLogin).

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
        description = "Extra gamescope arguments";
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
    (lib.mkIf cfg.gamescope.enable {
      programs.steam.gamescopeSession = {
        enable = true;
        args = cfg.gamescope.args;
      };
    })

    #---------------------------
    # Session Switcher
    #---------------------------
    # steamos-session-select: writes target session to /var/lib/sddm/state.conf
    # and terminates the current session so SDDM auto-login picks it up.
    # sddm-session group makes state.conf group-writable — no sudo needed.
    (lib.mkIf cfg.gamescope.sessionSwitcher.enable {
      features.desktop.autoLogin.enable = lib.mkForce true;

      users.groups.sddm-session = { };
      users.users.${config.user.name}.extraGroups = [ "sddm-session" ];

      systemd.tmpfiles.rules = [
        "f /var/lib/sddm/state.conf 0664 sddm sddm-session -"
        "Z /var/lib/sddm/state.conf 0664 sddm sddm-session -"
      ];

      environment.systemPackages = [
        (pkgs.writeShellScriptBin "steamos-session-select" ''
          set -euo pipefail
          SDDM_STATE="/var/lib/sddm/state.conf"
          case "''${1:-desktop}" in
            desktop)   SESSION="${if config.features.desktop.wm == "kde" then "plasma" else "hyprland"}" ;;
            gamescope|steam) SESSION="steam" ;;
            *) echo "Usage: steamos-session-select [desktop|gamescope]" >&2; exit 1 ;;
          esac
          if [ -f "$SDDM_STATE" ] && grep -q "^Session=" "$SDDM_STATE"; then
            ${pkgs.gnused}/bin/sed -i "s|^Session=.*|Session=$SESSION.desktop|" "$SDDM_STATE"
          elif [ -f "$SDDM_STATE" ] && grep -q "^\[Last\]" "$SDDM_STATE"; then
            ${pkgs.gnused}/bin/sed -i "/^\[Last\]/a Session=$SESSION.desktop" "$SDDM_STATE"
          else
            printf '[Last]\nSession=%s.desktop\n' "$SESSION" > "$SDDM_STATE"
          fi
          loginctl terminate-session "''${XDG_SESSION_ID:-self}"
        '')
      ];
    })

  ]);
}
