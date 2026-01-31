{ config, pkgs, lib, ... }:

{
  gtk = {
    enable = true;
    iconTheme = {
      package = lib.mkForce (pkgs.catppuccin-papirus-folders.override {
        flavor = config.catppuccin.flavor;
        accent = config.catppuccin.accent;
      });
      name = lib.mkForce "Papirus-Dark";
    };
  };
}
