{
  config,
  pkgs,
  inputs,
  ...
}:

{
  imports = [
    ./disko.nix
    ./hardware-configuration.nix

    ../../modules
  ];

  networking.hostName = "samuels-pc";

  # ─── Host-specific overrides ─────────────────────────────────────────────────
  theme.wallpaper = "Lake 4.png";  # Filename in encrypted backgrounds archive

  # Ensure samuel owns /mnt/games (mounted by disko)
  systemd.tmpfiles.rules = [
    "Z /mnt/games 0755 samuel users -"
  ];

  displays.monitors = [
    {
      name = "DP-1";
      width = 2560;
      height = 1440;
      refreshRate = 165;
      x = 2560;
      y = 0;
      workspaces = [
        1
        2
        3
        4
      ];
    }
    {
      name = "DP-2";
      width = 2560;
      height = 1440;
      refreshRate = 165;
      x = 0;
      y = 0;
      workspaces = [
        5
        6
        7
        8
      ];
    }
  ];

  system.stateVersion = "25.11";
}
