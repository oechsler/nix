{ lib, config, ... }:

let
  cfg = config.features.audio;
in
{
  options.features.audio = {
    enable = (lib.mkEnableOption "audio support (PipeWire)") // { default = true; };
  };

  config = lib.mkIf cfg.enable {
    services.pulseaudio.enable = false;
    security.rtkit.enable = true;

    services.pipewire = {
      enable = true;
      alsa.enable = true;
      alsa.support32Bit = true;
      pulse.enable = true;
    };
  };
}
