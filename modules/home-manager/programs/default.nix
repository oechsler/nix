{ config, pkgs, ... }:

{
  imports = [
    ./apps.nix
    ./browsers.nix
    ./development.nix
    ./fish.nix
    ./git.nix
    ./neovim.nix
    ./terminal.nix
    ./tmux.nix
    ./tools.nix
  ];
}
