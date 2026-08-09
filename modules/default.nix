# Top-level Modules Entry Point
#
# This module imports all system-level module categories.
# Everything lives under system/ — desktop modules (sddm, hyprland, kde)
# and terminal are imported from system/default.nix.

{ ... }:

{
  imports = [
    ./system
  ];
}
