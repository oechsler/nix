# Input Device Configuration
#
# This module defines scroll direction options for input devices.
#
# Configuration:
#   input.mouse.naturalScroll = true;      # Natural scroll for mice (default: true)
#   input.touchpad.naturalScroll = true;   # Natural scroll for touchpads (default: true)
#
# Natural scroll:
# - true = macOS/mobile style (swipe up to scroll down)
# - false = traditional style (swipe up to scroll up)
#
# Implementation:
# - Hyprland: Applied in hyprland/default.nix input settings
# - KDE: Applied in kde/theme.nix via libinput per-device config

{ lib, ... }:

{
  options.input = {
    mouse.naturalScroll = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Natural (reverse) scroll direction for mice";
    };
    touchpad.naturalScroll = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Natural (reverse) scroll direction for touchpads";
    };
  };
}
