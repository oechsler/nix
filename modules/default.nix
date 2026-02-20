# Top-level Modules Entry Point
#
# This module imports all system-level module categories:
# - system/  - System configuration (boot, networking, users, etc.)
# - desktop/ - Desktop environments (Hyprland, KDE, SDDM)
# - programs/ - System-level program configuration

{ ... }:

{
  imports = [
    ./system
    ./desktop
    ./programs
  ];
}
