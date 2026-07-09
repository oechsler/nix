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
# - Dim on AC / Lock on battery: 300s (5min)
# - Suspend on battery: 300s (5min)
# - Lock + suspend on AC: 1800s (30min)

{
  idle.timeouts = {
    dimBattery = 120;
    dimAcLockBattery = 300;
    suspendBattery = 300;
    lockSuspendAc = 1800;
  };
}
