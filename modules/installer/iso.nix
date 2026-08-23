# NixOS Installer ISO Configuration
#
# Builds a graphical multi-host installer with prebuilt system closures.

{
  lib,
  pkgs,
  diskoPackage,
  hostClosures,
  hostManifest,
  ...
}:

{
  networking.networkmanager.enable = true;

  security.sudo = {
    enable = true;
    wheelNeedsPassword = false;
  };

  isoImage.edition = "plasma6";

  services.desktopManager.plasma6 = {
    enable = true;
    enableQt5Integration = false;
  };

  services.displayManager = {
    plasma-login-manager.enable = true;
    autoLogin = {
      enable = true;
      user = "nixos";
    };
  };

  programs.kde-pim.enable = false;

  environment.systemPackages = [
    diskoPackage
    pkgs.git
    pkgs.jq
    pkgs.kdePackages.kdialog
    pkgs.kdePackages.konsole
  ];

  environment.etc = {
    "nixos-installer/manifest.json".text = builtins.toJSON hostManifest;
    "nixos-installer/install.sh".source = ../../install.sh;
    "nixos-installer/repo".source = ../../.;
    "xdg/autostart/nixos-installer.desktop".text = ''
      [Desktop Entry]
      Type=Application
      Name=NixOS Installer
      Comment=Install a prebuilt NixOS host
      Exec=${pkgs.kdePackages.konsole}/bin/konsole -e ${pkgs.sudo}/bin/sudo ${pkgs.bash}/bin/bash /etc/nixos-installer/install.sh --iso
      Terminal=false
      Categories=System;
    '';
  };

  systemd.user.services.nixos-installer = {
    description = "NixOS graphical installer";
    after = [ "graphical-session.target" ];
    partOf = [ "graphical-session.target" ];
    wantedBy = [ "graphical-session.target" ];
    serviceConfig = {
      Type = "exec";
      ExecStart = "${pkgs.kdePackages.konsole}/bin/konsole --hold -e ${pkgs.sudo}/bin/sudo ${pkgs.bash}/bin/bash /etc/nixos-installer/install.sh --iso";
      Restart = "on-failure";
      RestartSec = 2;
    };
  };

  isoImage.storeContents = lib.attrValues hostClosures;
}
