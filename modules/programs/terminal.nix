# Terminal Shell Configuration (System-level)
#
# This module enables Fish shell at the system level.
#
# Why system-level:
# - Makes Fish available as a login shell
# - Required for users.users.*.shell = pkgs.fish
#
# User-level configuration:
# - See home-manager/programs/fish.nix for shell customization
# - Aliases, functions, plugins, prompt are configured there
#
# Note: This only enables Fish system-wide, it doesn't configure it.

{ config, pkgs, ... }:

{
  # Fish at system level (used as login shell)
  programs.fish.enable = true;
}
