# samuels-pc Host Configuration
#
# Desktop workstation configuration.
#
# Hardware:
# - Dual 1440p 165Hz monitors (DP-1, DP-2)
# - Dedicated /mnt/games partition (1TB for Steam library)
#
# Features:
# - Secure Boot enabled
# - Dual-boot setup (Windows on separate disk)
# - Hyprland desktop (can switch to KDE in flake)
#
# Theme:
# - Catppuccin Lavender accent
# - Lake 4.png wallpaper
#
# Monitor layout:
# - DP-1 (right): Workspaces 1-4
# - DP-2 (left): Workspaces 5-8

{ ... }:

{
  imports = [
    ./disko.nix
    ./hardware-configuration.nix
    ./luks.nix

    ../../modules
  ];

  networking.hostName = "samuels-pc";

  #===========================
  # Host-specific Overrides
  #===========================
  theme.catppuccin.accent = "lavender";
  theme.wallpaper = "Lake 4.png";

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

  # Fallback password (TOTP is primary auth — see auth.nix)
  # Change with: mkpasswd -m sha-512
  user.hashedPassword = "$6$P1igUfSBc.///vJD$g.8f4tpbqwZAOpu9tMyD06fDuJ/trn6QVUgLapJ8.F8EPVMEFGXJ9wpB8nTTpblw4ueFTm4S.2oCLsXtuBzpB0";

  features = {
    secureBoot.enable = true;
  };

  system.stateVersion = "25.11";
}
