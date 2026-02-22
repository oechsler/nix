# Home Manager Integration
#
# This module integrates Home Manager for user-level configuration.
#
# How it works:
# - Uses flake's home-manager NixOS module
# - Automatically sets basic home-manager values (username, home directory, state version)
# - Optionally imports host-specific home.nix from hosts/{hostname}/home.nix (if exists)
# - Passes system config to home-manager (fonts, theme, features, etc.)
#
# Passed to Home Manager modules:
# - fonts: config.fonts.defaults (UI/monospace fonts, sizes)
# - theme: config.theme (Catppuccin, wallpaper, gaps, borders)
# - locale: config.locale (timezone, language, keyboard)
# - user: config.user (name, fullName, email, github)
# - features: config.features (desktop, development, apps, etc.)
# - displays: config.displays (monitor configuration)
# - input: config.input (mouse/touchpad natural scroll)
#
# Integrations:
# - Catppuccin theming (catppuccin.homeModules.catppuccin)
# - SOPS secrets (sops-nix.homeManagerModules.sops)
# - KDE Plasma config (plasma-manager.homeModules.plasma-manager)
#
# Optional host-specific home.nix:
# - Only needed for host-specific user configuration (e.g., idle timeouts)
# - If missing, only common modules are loaded

{ config, inputs, lib, ... }:

let
  # Check if host has a custom home.nix file
  hostHomeNix = ../../hosts/${config.networking.hostName}/home.nix;
  hasHostHomeNix = builtins.pathExists hostHomeNix;
in
{
  home-manager = {
    useGlobalPkgs = true;
    extraSpecialArgs = {
      inherit inputs;
      inherit (config) locale user features displays input;
      inherit (config) theme;
      fonts = config.fonts.defaults;
    };
    users.${config.user.name} = {
      imports = [
        inputs.catppuccin.homeModules.catppuccin
        inputs.sops-nix.homeManagerModules.sops
        inputs.plasma-manager.homeModules.plasma-manager
      ]
      ++ lib.optional hasHostHomeNix hostHomeNix;

      # Automatic defaults (can be overridden in host-specific home.nix)
      home = {
        username = config.user.name;
        homeDirectory = "/home/${config.user.name}";
        stateVersion = config.system.stateVersion;
      };

      programs.home-manager.enable = true;
    };
    backupFileExtension = "bak";
  };
}
