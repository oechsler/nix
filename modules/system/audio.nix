# Audio Configuration
#
# This module configures audio support using PipeWire.
#
# Features:
# - PipeWire audio server (modern replacement for PulseAudio)
# - ALSA compatibility layer (32-bit and 64-bit)
# - PulseAudio compatibility layer
# - RTKit for realtime audio scheduling
#
# Configuration:
#   features.audio.enable = true;  # Enable audio support (default: true)
#
# Why PipeWire:
# - Lower latency than PulseAudio
# - Better Bluetooth audio quality
# - Pro audio support (JACK compatibility)
# - Video processing pipeline integration

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
