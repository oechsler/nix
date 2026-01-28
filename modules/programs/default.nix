{ config, pkgs, ... }:

{
  imports = [
    ./system-tools.nix
    ./terminal.nix
    ./development.nix
    ./browsers.nix
  ];  
}
