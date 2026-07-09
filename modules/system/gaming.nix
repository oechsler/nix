# Gaming Configuration
#
# Installed:
# - Steam + Proton-GE     — gaming platform with enhanced Windows compatibility
# - Gamemode              — CPU governor + realtime scheduling when a game runs
# - Gamescope             — Wayland compositor for gaming (frame limiting, upscaling)
# - MangoHud              — in-game FPS/GPU/CPU overlay
# - ProtonUp-Qt           — GUI to manage Proton-GE versions
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
in
{
  options.features.gaming = {
    enable = (lib.mkEnableOption "gaming support (Steam, Gamemode, Gamescope)") // {
      default = true;
    };
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [

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
          mangohud # in-game overlay: FPS, GPU/CPU load, temps, VRAM
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
