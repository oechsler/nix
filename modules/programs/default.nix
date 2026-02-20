# System-level Program Configuration
#
# This module imports system-level program configuration.
# Currently only contains terminal shell setup (Fish).
#
# User-level program config is in home-manager/programs/

{ config, pkgs, ... }:

{
  imports = [
    ./terminal.nix
  ];
}
