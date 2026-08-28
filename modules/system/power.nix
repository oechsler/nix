# Power Management Configuration
#
# This module configures power management behavior:
# - Power Profiles Daemon - Dynamic power profile switching (performance/balanced/power-saver)
# - Power button handling - Suspend by default, overridden by desktop environments
#
# Power button behavior:
# - System and Steam Machine session: Suspend immediately like SteamOS
# - Hyprland desktop: Inhibits logind and handles the button via Rofi power menu
# - KDE desktop: Inhibits logind through PowerDevil and uses KDE power settings
#
# Machine-type behavior (derived from features.hardware.formFactor):
# - Desktop: Lid switch ignore, AMD GPU runpm disabled
# - Laptop:  Lid switch suspend on battery, GPU runpm enabled

{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.features.hardware;
  isLaptop = cfg.formFactor == "laptop";
  isHyprlandLaptop = isLaptop && config.features.desktop.wm == "hyprland";
  hasAmdGpu = cfg.gpu == "amd";
  configuredExternalMonitor = lib.findFirst (
    monitor: !(builtins.match "^(eDP|LVDS|DPI)-.*" monitor.name != null)
  ) null config.displays.monitors;
in
{
  services.power-profiles-daemon.enable = true;

  services.acpid = lib.mkIf isHyprlandLaptop {
    enable = true;
    handlers.lid = {
      event = "button/lid.*";
      action = ''
        case "$1" in
          *close*) mode=off ;;
          *open*) mode=on ;;
          *) exit 0 ;;
        esac

        uid=$(id -u ${config.user.name})
        for socket in /run/user/$uid/hypr/*/.socket.sock; do
          [ -S "$socket" ] || continue
          instance=$(basename "$(dirname "$socket")")
          hyprctl() {
            runuser -u ${config.user.name} -- env XDG_RUNTIME_DIR=/run/user/$uid HYPRLAND_INSTANCE_SIGNATURE="$instance" ${pkgs.hyprland}/bin/hyprctl "$@"
          }
          monitors=$(hyprctl monitors -j)
          internal=$(printf '%s' "$monitors" | ${pkgs.jq}/bin/jq -r '[.[] | .name | select(test("^(eDP|LVDS|DPI)-"))][0] // empty')
          external=$(printf '%s' "$monitors" | ${pkgs.jq}/bin/jq -r --arg internal "$internal" --arg configured "${
            if configuredExternalMonitor == null then "" else configuredExternalMonitor.name
          }" '[.[] | select(if $configured != "" then .name == $configured else .name != $internal end)][0].name // empty')
          [ -n "$internal" ] && [ -n "$external" ] || continue
          if [ "$mode" = on ]; then
            hyprctl dispatch "hl.dsp.dpms({ mode = \"on\", monitor = \"$internal\" })"
            sleep 1
            hyprctl dispatch "hl.dsp.workspace.move({ monitor = \"$internal\" })"
            hyprctl dispatch "hl.dsp.focus({ monitor = \"$internal\" })"
          else
            hyprctl dispatch "hl.dsp.workspace.move({ monitor = \"$external\" })"
            hyprctl dispatch "hl.dsp.dpms({ mode = \"off\", monitor = \"$internal\" })"
            hyprctl dispatch "hl.dsp.focus({ monitor = \"$external\" })"
          fi
        done
      '';
    };
  };

  services.logind.settings.Login = {
    InhibitDelayMaxSec = "2s";
    # PowerDevil inhibits this while a KDE session is active. At SDDM there is
    # no inhibitor, so the power button still suspends at the login screen.
    HandlePowerKey = "suspend";
    HandlePowerKeyLongPress = "poweroff";
    HandleSuspendKey = "suspend";
    HandleHibernateKey = "suspend";
    HandleLidSwitch = if isLaptop then "suspend" else "ignore";
    HandleLidSwitchExternalPower = "ignore";
    HandleLidSwitchDocked = "ignore";
    LidSwitchIgnoreInhibited = if isLaptop then "yes" else "no";
  };

  systemd.sleep.settings.Sleep = {
    SuspendState = [ "mem" ];
    HibernateDelaySec = "360min";
    AllowSuspend = true;
    AllowHibernation = false;
    AllowSuspendThenHibernate = false;
  };

  # amdgpu.runpm=0 disables GPU runtime PM.
  # On desktop/server: prevents BACO transition issues during suspend (prevents resume hangs).
  # On laptop: runtime PM must stay enabled to allow the GPU to power down on battery.
  boot.kernelParams = lib.optionals (hasAmdGpu && !isLaptop) [
    "amdgpu.runpm=0"
  ];
}
