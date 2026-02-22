# Home Manager Modules Entry Point
#
# This module imports user-level configuration categories:
# - programs/ - User applications and tools
# - desktop/ - Desktop environment customization
#
# These modules are loaded via system/home-manager.nix integration.

{ config, secretsFile, ... }:

{
  imports = [
    ./programs
    ./desktop
  ];

  # SOPS configuration for home-manager secrets (uses system-level secretsFile)
  sops = {
    defaultSopsFile = secretsFile;
    age.keyFile = "${config.home.homeDirectory}/.config/sops/age/keys.txt";
  };
}
