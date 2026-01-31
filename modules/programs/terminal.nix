{ config, pkgs, ... }:

{
  # Fish bleibt auf System-Ebene da es als Login-Shell gesetzt ist
  programs.fish.enable = true;
}