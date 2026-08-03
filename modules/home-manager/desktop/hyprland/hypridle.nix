# Hypridle Configuration (Idle Management)
#
# This module configures hypridle for automatic screen dimming, locking, and suspend.
#
# Key features:
# - Battery-aware behavior (different timings for AC vs battery)
# - Smooth screen dimming via brightnessctl (laptops) or hyprsunset gamma (desktops)
# - Automatic lock and suspend
# - Resume actions (restore brightness, turn on screen)
#
# Dimming approach per form factor:
# - Laptops: brightnessctl controls the internal display backlight (smooth steps)
# - Desktops: hyprsunset applies system-wide gamma to darken external monitors
#   (brightnessctl has no effect on monitors that lack a kernel backlight interface)
#
# Timeouts (from config.idle.*):
# - dimBattery: Dim screen on battery
# - suspendBattery: Lock + suspend on battery
# - dimAc: Dim screen on AC
# - suspendAc: Lock + suspend on AC
#
# Configuration options:
#   hypridle.dim.percent = 30;         # Target brightness percentage when dimmed (default: 30%)
#   hypridle.dim.stepPercent = 5;      # Brightness step size for smooth dim (default: 5%)
#   hypridle.dim.stepDelay = "0.1";    # Delay between steps (default: 0.05s)
#
# Battery detection:
# - Desktop without battery → always treated as AC
# - Laptop with battery → checks /sys/class/power_supply/*/online

{
  config,
  pkgs,
  lib,
  features,
  ...
}:

let
  inherit (config) idle;

  isLaptop = features.hardware.formFactor == "laptop";

  # ============================================================================
  # BATTERY DETECTION HELPERS
  # ============================================================================
  hasBattery = "(test -d /sys/class/power_supply/BAT0 || test -d /sys/class/power_supply/BAT1)";
  acOnline = "(cat /sys/class/power_supply/*/online 2>/dev/null | grep -q 1)";
  onBattery = "${hasBattery} && ! ${acOnline}";
  onAC = "! ${hasBattery} || ${acOnline}";

  # ============================================================================
  # BACKLIGHT DETECTION
  # ============================================================================
  hasBacklight = "(set -- /sys/class/backlight/*; test -e \"$1\")";

  # Smooth dim configuration
  dimPercent = config.hypridle.dim.percent;
  dimStepPercent = config.hypridle.dim.stepPercent;
  dimStepDelay = config.hypridle.dim.stepDelay;

  # ============================================================================
  # LAPTOP DIM (brightnessctl)
  # ============================================================================
  smoothDimLaptop = toString (
    pkgs.writeShellScript "smooth-dim-laptop" ''
      brightnessctl -s
      current=$(brightnessctl get)
      max=$(brightnessctl max)
      target=$((max * ${toString dimPercent} / 100))
      step=$((max * ${toString dimStepPercent} / 100))
      while [ "$current" -gt "$target" ]; do
        current=$((current - step))
        [ "$current" -lt "$target" ] && current=$target
        brightnessctl set "$current" -q
        sleep ${dimStepDelay}
      done
    ''
  );

  undimLaptop = toString (
    pkgs.writeShellScript "undim-laptop" ''
      brightnessctl -r
    ''
  );

  # ============================================================================
  # DESKTOP DIM (hyprsunset gamma)
  # ============================================================================
  # hyprsunset applies a global gamma ramp via zwlr_gamma_control.
  # gamma 1.0 = full brightness, gamma 0.30 = 30 % perceived brightness.
  # We keep the process alive (foreground) and store its PID so undim can kill it.
  #
  # When hyprsunset restarts (e.g. after a display sleep cycle) the gamma is
  # lost, so the listener re-applies it via on-resume.
  # DDC/CI (ddcutil) is handled separately via the brightness keybindings.
  dimDesktop = toString (
    pkgs.writeShellScript "dim-desktop" ''
      pidfile="''${XDG_RUNTIME_DIR:-/tmp}/hypridle-dim.pid"
      if [ -f "$pidfile" ]; then
        kill "$(cat "$pidfile")" 2>/dev/null || true
        rm -f "$pidfile"
      fi
      target_gamma=$(printf "%d.%02d" $((${toString dimPercent} / 100)) $((${toString dimPercent} % 100)))
      ${pkgs.hyprsunset}/bin/hyprsunset -g "$target_gamma" &
      echo $! > "$pidfile"
    ''
  );

  undimDesktop = toString (
    pkgs.writeShellScript "undim-desktop" ''
      pidfile="''${XDG_RUNTIME_DIR:-/tmp}/hypridle-dim.pid"
      if [ -f "$pidfile" ]; then
        kill "$(cat "$pidfile")" 2>/dev/null || true
        rm -f "$pidfile"
      fi
      ${pkgs.hyprsunset}/bin/hyprsunset -i
    ''
  );

  # ============================================================================
  # DIM / UNDIM (form-factor-aware at runtime)
  # ============================================================================
  #
  # Backlight presence is checked at runtime so the same script file works
  # on both laptops (has backlight → brightnessctl) and desktops (no backlight
  # → hyprsunset gamma).
  selectDim = toString (
    pkgs.writeShellScript "select-dim" ''
      if ${hasBacklight}; then
        ${smoothDimLaptop}
      else
        ${dimDesktop}
      fi
    ''
  );

  selectUndim = toString (
    pkgs.writeShellScript "select-undim" ''
      if ${hasBacklight}; then
        ${undimLaptop}
      else
        ${undimDesktop}
      fi
    ''
  );

  # ============================================================================
  # IDLE ACTION SCRIPTS
  # ============================================================================

  # Dim screen on battery
  dimBattery = toString (
    pkgs.writeShellScript "dim-battery" ''
      ${onBattery} && ${selectDim}
    ''
  );

  # Dim screen on AC
  dimAc = toString (
    pkgs.writeShellScript "dim-ac" ''
      ${onAC} && ${selectDim}
    ''
  );

  # Lock + suspend on battery
  suspendBattery = toString (
    pkgs.writeShellScript "suspend-battery" ''
      ${onBattery} && loginctl lock-session && systemctl suspend
    ''
  );

  # Lock + suspend on AC
  suspendAc = toString (
    pkgs.writeShellScript "suspend-ac" ''
      ${onAC} && loginctl lock-session && systemctl suspend
    ''
  );

  # ============================================================================
  # LISTENERS
  # ============================================================================

  # Shared listeners (both desktop and laptop)
  sharedListeners = [
    {
      timeout = idle.timeouts.dimAc;
      on-timeout = dimAc;
      on-resume = selectUndim;
    }
    {
      timeout = idle.timeouts.suspendAc;
      on-timeout = suspendAc;
    }
  ];

  # Laptop-only listeners (battery-specific)
  laptopListeners = [
    {
      timeout = idle.timeouts.dimBattery;
      on-timeout = dimBattery;
      on-resume = selectUndim;
    }
    {
      timeout = idle.timeouts.suspendBattery;
      on-timeout = suspendBattery;
    }
  ];
in
{
  #===========================
  # Options
  #===========================

  options.hypridle.dim = {
    percent = lib.mkOption {
      type = lib.types.ints.between 1 100;
      default = 30;
      description = "Target brightness percentage when dimmed";
    };
    stepPercent = lib.mkOption {
      type = lib.types.ints.between 1 100;
      default = 5;
      description = "Brightness step size for smooth dimming";
    };
    stepDelay = lib.mkOption {
      type = lib.types.str;
      default = "0.05";
      description = "Delay between dim steps in seconds";
    };
  };

  #===========================
  # Configuration
  #===========================

  config = {
    home.packages =
      lib.optionals isLaptop [ pkgs.brightnessctl ] ++ lib.optionals (!isLaptop) [ pkgs.hyprsunset ];

    services.hypridle = {
      enable = true;

      settings = {
        general = {
          lock_cmd = "pidof hyprlock || hyprlock";
          before_sleep_cmd = "loginctl lock-session";
          after_sleep_cmd = "${pkgs.runtimeShell} -c 'for i in 1 2 3; do hyprctl dispatch dpms on 2>/dev/null && break; sleep 0.5; done'";
        };

        listener = sharedListeners ++ lib.optionals isLaptop laptopListeners;
      };
    };
  };
}
