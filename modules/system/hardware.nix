# Hardware Configuration
#
# This module configures hardware-related system services:
# - CoolerControl - Fan control GUI (monitors and controls system fans)
# - zram swap - Compressed RAM swap (100% of RAM, improves performance)
# - Printing disabled (no CUPS service)
#
# zram swap:
# - Uses 100% of available RAM for compressed swap space
# - Improves performance on systems with limited RAM
# - Compression ratio typically 2-3x

{ ... }:

{
  programs.coolercontrol.enable = true;
  services.printing.enable = false;
  zramSwap = {
    enable = true;
    memoryPercent = 100;
  };
}
