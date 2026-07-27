# Audio Configuration
#
# This module configures audio support using PipeWire.
#
# Features:
# - PipeWire audio server (modern replacement for PulseAudio)
# - ALSA compatibility layer (32-bit and 64-bit)
# - PulseAudio compatibility layer
# - RTKit for realtime audio scheduling
# - Hardware mute before sleep (prevents looping during suspend)
#
# Configuration:
#   features.audio.enable = true;  # Enable audio support (default: true)
#
# Why PipeWire:
# - Lower latency than PulseAudio
# - Better Bluetooth audio quality
# - Pro audio support (JACK compatibility)
# - Video processing pipeline integration

{
  lib,
  config,
  pkgs,
  ...
}:

let
  cfg = config.features.audio;
in
{
  options.features.audio = {
    enable = (lib.mkEnableOption "audio support (PipeWire)") // {
      default = true;
    };
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

    environment.etc."systemd/system-sleep/audio-mute" = {
      mode = "0755";
      text = ''
        #!${pkgs.runtimeShell}
        TO=${pkgs.coreutils}/bin/timeout

        mute_all() {
          $TO 0.5 ${pkgs.alsa-utils}/bin/amixer scontrols 2>/dev/null \
            | ${pkgs.coreutils}/bin/cut -d"'" -f2 \
            | while read -r ctrl; do
              $TO 0.5 ${pkgs.alsa-utils}/bin/amixer --quiet set "$ctrl" "$1" \
                2>/dev/null
            done
        }
        case "$1" in
          pre)  mute_all mute ;;
          post) mute_all unmute ;;
        esac
      '';
    };
  };
}
