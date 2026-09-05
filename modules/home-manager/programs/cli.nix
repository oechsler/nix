# Shared command-line tools for desktop and headless hosts.
#
# These programs do not require a graphical terminal emulator and are available
# in both interactive shells and headless sessions.

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
    ouch
    procs
    ripgrep
    sd
  ];
}
