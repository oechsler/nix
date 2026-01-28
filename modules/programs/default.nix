{ config, pkgs, ... }:

{
  imports = [
    ./browsers.nix
    ./dev-tools.nix
    ./system-tools.nix
  ];  
}
