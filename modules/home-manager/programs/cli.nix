# Shared command-line tools for desktop and headless hosts.

{ pkgs, ... }:

{
  programs = {
    fastfetch.enable = true;

    starship = {
      enable = true;
      enableFishIntegration = true;
    };

    eza = {
      enable = true;
      enableFishIntegration = false;
      icons = "auto";
      extraOptions = [ "--group-directories-first" ];
    };

    bat.enable = true;
    bottom.enable = true;

    fzf = {
      enable = true;
      enableFishIntegration = true;
    };

    zoxide = {
      enable = true;
      enableFishIntegration = true;
    };
  };

  home.packages = with pkgs; [
    dust
    fd
    jq
    procs
    ripgrep
    sd
  ];
}
