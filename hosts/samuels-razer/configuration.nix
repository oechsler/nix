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
    ./luks.nix

    ../../modules
  ];

  networking.hostName = "samuels-razer";

  # ─── Host-specific overrides ─────────────────────────────────────────────────
  displays.monitors = [
    {
      name = "eDP-1";
      width = 3200;
      height = 1800;
      refreshRate = 60;
      scale = 1.6;
      workspaces = [
        1
        2
        3
        4
      ];
    }
  ];

  features.desktop.wm = "kde";
  fonts.defaults.terminalSize = 10;

  features.gaming.enable = false;

  system.stateVersion = "25.11";
}
