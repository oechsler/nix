{ config, pkgs, ... }:

{
  users.users.samuel = {
    isNormalUser = true;
    description = "Samuel Oechsler";
    extraGroups = [ "networkmanager" "wheel" ];
    shell = pkgs.fish;
  };
}
