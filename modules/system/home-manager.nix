# Home Manager Integration
#
# This module integrates Home Manager for user-level configuration.
#
# How it works:
# - Uses flake's home-manager NixOS module
# - Imports host-specific home.nix from hosts/{hostname}/home.nix
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

{ config, inputs, ... }:

{
  home-manager = {
    useGlobalPkgs = true;
    extraSpecialArgs = {
      inherit inputs;
      fonts = config.fonts.defaults;
      theme = config.theme;
      locale = config.locale;
      user = config.user;
      features = config.features;
      displays = config.displays;
      input = config.input;
    };
    users.${config.user.name} = {
      imports = [
        ../../hosts/${config.networking.hostName}/home.nix
        inputs.catppuccin.homeModules.catppuccin
        inputs.sops-nix.homeManagerModules.sops
        inputs.plasma-manager.homeModules.plasma-manager
      ];
    };
    backupFileExtension = "bak";
  };
}
