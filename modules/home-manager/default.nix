# Home Manager Modules Entry Point
#
# This module imports user-level configuration categories:
# - programs/ - User applications and tools
# - desktop/ - Desktop environment customization
#
# These modules are loaded via system/home-manager.nix integration.

{ ... }:

{
  imports = [
    ./programs
    ./desktop
  ];
}
