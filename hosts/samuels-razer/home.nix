# samuels-razer Home Manager Configuration
#
# Host-specific user configuration for samuels-razer (Razer Blade Stealth 13 laptop).
#
# Idle timeouts are kept at the laptop defaults from common/idle.nix.
# Listed here explicitly so the intent is clear and changes to the defaults
# don't silently affect this battery-powered machine.
#
# Timeouts (in seconds):
# - Dim on battery: 120s (2min)
# - Lock + suspend on battery: 300s (5min)
# - Dim on AC: 300s (5min)
# - Lock + suspend on AC: 1800s (30min)

{
  idle.timeouts = {
    dimBattery = 120;
    suspendBattery = 300;
    dimAc = 300;
    suspendAc = 1800;
  };
}
