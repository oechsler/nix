# samuels-pc Home Manager Configuration
#
# User-level configuration for samuels-pc.
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

{ user, ... }:

{
  imports = [
    ../../modules/home-manager
  ];

  home.username = user.name;
  home.homeDirectory = "/home/${user.name}";
  home.stateVersion = "25.11";

  programs.home-manager.enable = true;

  # Longer idle timeouts for desktop PC
  idle.timeouts = {
    dimBattery = 300;
    dimAcLockBattery = 600;
    suspendBattery = 600;
    lockSuspendAc = 3600;
  };
}
