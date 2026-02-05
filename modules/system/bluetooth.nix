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
