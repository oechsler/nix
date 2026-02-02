{ config, pkgs, fonts, ... }:

{
  programs.kitty = {
    enable = true;
    font = {
      name = fonts.monospace;
      size = fonts.size;
    };
  };

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
