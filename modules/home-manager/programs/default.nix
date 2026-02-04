{ config, pkgs, ... }:

{
  imports = [
    ./apps.nix
    ./browsers.nix
    ./terminal.nix
    ./development.nix
    ./tools.nix
  ];
}
