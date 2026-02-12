{ config, pkgs, ... }:

{
  programs.htop.enable = true;

  programs.gh = {
    enable = true;
    settings.git_protocol = "ssh";
  };

  programs.yazi.enable = true;
}
