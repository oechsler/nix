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
    "nixos-installer/manifest.json".text = builtins.toJSON { hosts = hostManifest; };
    "nixos-installer/install.sh".source = ../../install.sh;
    "nixos-installer/repo".source = ../../.;
    "nixos-installer/NixOS Installer.desktop".text = ''
      [Desktop Entry]
      Type=Application
      Name=NixOS Installer
      Comment=Install a prebuilt NixOS host
      Exec=${pkgs.kdePackages.konsole}/bin/konsole -e /run/wrappers/bin/sudo ${pkgs.bash}/bin/bash /etc/nixos-installer/install.sh --iso
      Terminal=false
      Categories=System;
    '';
  };

  systemd.tmpfiles.rules = [
    "d /home/nixos/Desktop 0755 nixos users - -"
    "C /home/nixos/Desktop/NixOS Installer.desktop 0755 nixos users - /etc/nixos-installer/NixOS Installer.desktop"
  ];

  isoImage.storeContents = lib.attrValues hostClosures;
}
