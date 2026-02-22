# samuels-pc Home Manager Configuration
#
# Host-specific user configuration for samuels-pc.
#
# Customizations:
# - Extended idle timeouts (desktop PC, always on AC power)
# - Longer times before dim/lock/suspend compared to laptop
#
# Timeouts (in seconds):
# - Dim on battery: 300s (5min) vs laptop 120s (2min)
# - Dim on AC / Lock on battery: 600s (10min) vs laptop 300s (5min)
# - Suspend on battery: 600s (10min) vs laptop 300s (5min)
# - Lock + suspend on AC: 3600s (60min) vs laptop 1800s (30min)
#
# Note: Basic values (username, homeDirectory, stateVersion, etc.) are set
# automatically in modules/system/home-manager.nix and don't need to be
# specified here.

{
  # Longer idle timeouts for desktop PC
  idle.timeouts = {
    dimBattery = 300;
    dimAcLockBattery = 600;
    suspendBattery = 600;
    lockSuspendAc = 3600;
  };
}
