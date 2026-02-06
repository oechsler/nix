{ config, pkgs, inputs, ... }:

{
  imports = [
    ./disko.nix
    ./hardware-configuration.nix

    ../../modules
  ];

  networking.hostName = "samuels-pc";

  # ─── Host-specific overrides ─────────────────────────────────────────────────
  theme.wallpaper = ../../backgrounds/nix-black-4k.png;

  # Ensure samuel owns /mnt/games (mounted by disko)
  systemd.tmpfiles.rules = [
    "Z /mnt/games 0755 samuel users -"
  ];

  displays.monitors = [
    { name = "DP-1"; width = 2560; height = 1440; refreshRate = 165; x = 2560; y = 0; }
    { name = "DP-2"; width = 2560; height = 1440; refreshRate = 165; x = 0; y = 0; }
  ];

  system.stateVersion = "25.11";
}
