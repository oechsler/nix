# samuels-pc Home Manager Configuration
#
# Host-specific user configuration for samuels-pc.
#
# Customizations:
# - Extended idle timeouts (desktop PC, always on AC power)
# - Longer times before dim/suspend compared to laptop
#
# Timeouts (in seconds):
# - Dim on AC: 600s (10min) vs laptop 300s (5min)
# - Lock + suspend on AC: 3600s (60min) vs laptop 1800s (30min)
#
# Note: Battery-specific timeouts (dimBattery, suspendBattery) are omitted
# because desktops have no battery. Basic values (username, homeDirectory,
# stateVersion, etc.) are set automatically in modules/system/home-manager.nix.

{
  # Longer idle timeouts for desktop PC
  idle.timeouts = {
    dimAc = 600;
    suspendAc = 3600;
  };
}
