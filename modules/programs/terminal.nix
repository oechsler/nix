{ config, pkgs, ... }:

{
  programs.fish.enable = true;

  environment.systemPackages = with pkgs; [
    kitty

    starship

    eza
    bat
    zoxide
  ];
}