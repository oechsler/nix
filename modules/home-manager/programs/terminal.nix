{ config, pkgs, ... }:

{
  programs.kitty.enable = true;

  programs.starship = {
    enable = true;
    enableFishIntegration = true;
  };

  programs.eza = {
    enable = true;
    enableFishIntegration = true;
  };

  programs.bat.enable = true;

  programs.zoxide = {
    enable = true;
    enableFishIntegration = true;
  };
}
