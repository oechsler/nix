# Bluetooth Configuration
#
# This module enables Bluetooth hardware support.
#
# Configuration:
#   features.bluetooth.enable = true;  # Enable Bluetooth (default: true)
#
# Behavior:
# - Powers on Bluetooth adapter at boot
# - Integrates with PipeWire for audio (see audio.nix)
# - Desktop environments provide GUI for pairing (GNOME Settings, KDE Settings)

{ lib, config, ... }:

let
  cfg = config.features.bluetooth;
in
{
  options.features.bluetooth = {
    enable = (lib.mkEnableOption "bluetooth support") // { default = true; };
  };

  config = lib.mkIf cfg.enable {
    hardware.bluetooth = {
      enable = true;
      powerOnBoot = true;
    };
  };
}
