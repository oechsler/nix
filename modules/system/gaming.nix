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

  ]);

}
