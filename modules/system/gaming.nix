# Gaming Configuration
#
# This module enables gaming support with Steam and performance tools.
#
# Configuration:
#   features.gaming.enable = true;       # Enable gaming support (default: true)
#   features.gaming.gpu = "amd";         # GPU vendor for hardware encoding (null | "amd" | "intel")
#   features.gaming.gamescope.enable = true;  # Steam as standalone Wayland session (media PC / Big Picture)
#   features.gaming.gamescope.args = [];      # Extra gamescope args (e.g. ["-W 1920" "-H 1080" "-r 60"])
#
# Installed:
# - Steam + Proton-GE - Gaming platform with enhanced Windows compatibility
# - Gamemode - Automatic performance optimizations for games
# - Gamescope - Wayland compositor for gaming (frame limiting, upscaling)
# - MangoHud - In-game FPS/GPU/CPU overlay
# - ProtonUp-Qt - GUI to manage Proton-GE versions
#
# Features:
# - Proton-GE in Steam as extra compatibility tool (better game support than stock Proton)
# - Gamemode: CPU performance governor + realtime scheduling + renice when game runs
# - Steam Remote Play firewall ports opened automatically
# - Network + VM tuning for low-latency gaming and streaming
# - Gamescope Session: registers a "Steam" Wayland session in SDDM — selectable at login
#   alongside the regular desktop (Hyprland/KDE). Ideal for media PCs / Big Picture Mode.
#
# GPU-specific (features.gaming.gpu):
#   "amd"   — VA-API via Mesa radeonsi (VCN encoder on RDNA2+)
#   "intel" — VA-API via intel-media-driver (iHD, Gen 9 / Broadwell+)

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
      enable = lib.mkEnableOption "Steam gamescope session (standalone Wayland session selectable in SDDM — ideal for media PCs / Big Picture Mode)";
      args = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "Extra arguments passed to gamescope in the Steam session";
        example = [ "-W 1920" "-H 1080" "-r 60" "--hdr-enabled" ];
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
    # Registers a standalone "Steam" Wayland session in SDDM.
    # At login the user can pick between the regular desktop and this session.
    # Inside the session: gamescope runs as the Wayland compositor with Steam in
    # Big Picture Mode — ideal for media PCs / living room setups.
    #
    # Automatically disabled when features.gaming.enable = false (this whole
    # block is guarded by lib.mkIf cfg.enable above).
    (lib.mkIf cfg.gamescope.enable {
      programs.steam.gamescopeSession = {
        enable = true;
        args = cfg.gamescope.args;
      };
    })

  ]);
}
