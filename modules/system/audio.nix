# Audio Configuration
#
# This module configures audio support using PipeWire.
#
# Features:
# - PipeWire audio server (modern replacement for PulseAudio)
# - ALSA compatibility layer (32-bit and 64-bit)
# - PulseAudio compatibility layer
# - RTKit for realtime audio scheduling
# - Audio sink suspend before sleep (prevents looping during suspend)
#
# Configuration:
#   features.audio.enable = true;  # Enable audio support (default: true)
#
# Why PipeWire:
# - Lower latency than PulseAudio
# - Better Bluetooth audio quality
# - Pro audio support (JACK compatibility)
# - Video processing pipeline integration

{ lib, config, pkgs, ... }:

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

    # Mute audio before sleep to prevent buffer looping (stuttering sound while
    # the system transitions to sleep). The sound card's ALSA buffer can loop
    # the last samples when the kernel suspends the device — muting the sink
    # makes this inaudible. Audio is unmuted on resume.
    systemd.services.pipewire-sleep-mute = {
      description = "Mute PipeWire sinks before system sleep";
      before = [ "sleep.target" ];
      wantedBy = [ "sleep.target" ];
      serviceConfig.Type = "oneshot";
      script = ''
        for dir in /run/user/*/; do
          uid=$(${pkgs.coreutils}/bin/basename "$dir")
          if [ "$uid" != "0" ] && [ -S "$dir/pipewire-0" ]; then
            XDG_RUNTIME_DIR="$dir" ${pkgs.wireplumber}/bin/wpctl set-mute @DEFAULT_AUDIO_SINK@ 1 2>/dev/null || true
            XDG_RUNTIME_DIR="$dir" ${pkgs.wireplumber}/bin/wpctl set-mute @DEFAULT_AUDIO_SOURCE@ 1 2>/dev/null || true
          fi
        done
      '';
    };

    systemd.services.pipewire-sleep-unmute = {
      description = "Unmute PipeWire sinks after system sleep";
      after = [ "sleep.target" ];
      wantedBy = [ "sleep.target" ];
      serviceConfig.Type = "oneshot";
      script = ''
        ${pkgs.coreutils}/bin/sleep 2
        for dir in /run/user/*/; do
          uid=$(${pkgs.coreutils}/bin/basename "$dir")
          if [ "$uid" != "0" ] && [ -S "$dir/pipewire-0" ]; then
            XDG_RUNTIME_DIR="$dir" ${pkgs.wireplumber}/bin/wpctl set-mute @DEFAULT_AUDIO_SINK@ 0 2>/dev/null || true
            XDG_RUNTIME_DIR="$dir" ${pkgs.wireplumber}/bin/wpctl set-mute @DEFAULT_AUDIO_SOURCE@ 0 2>/dev/null || true
          fi
        done
      '';
    };
  };
}
