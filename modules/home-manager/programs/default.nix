{ config, pkgs, ... }:

{
  imports = [
    ./browsers.nix
    ./terminal.nix
    ./development.nix
    ./tools.nix
  ];
}
