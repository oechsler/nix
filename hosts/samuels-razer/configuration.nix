{ config, pkgs, inputs, ... }:

{
  imports = [
    ./disko.nix
    ./hardware-configuration.nix

    ../../modules
  ];

  networking.hostName = "samuels-razer";

  # ─── Host-specific overrides ─────────────────────────────────────────────────
  displays.monitors = [
    { name = "eDP-1"; width = 3200; height = 1800; refreshRate = 60; scale = 1.6; }
  ];

  features.desktop.wm = "kde";

  fonts.defaults.terminalSize = 10;

  system.stateVersion = "25.11";
}
