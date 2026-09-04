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

let
  installerCommand = pkgs.writeShellScriptBin "nixos-installer" ''
    exec /run/wrappers/bin/sudo ${pkgs.bash}/bin/bash /etc/nixos-installer/repo/install.sh --iso "$@"
  '';
in
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
    pkgs.kdePackages.konsole
    installerCommand
  ];

  environment.etc = {
    "nixos-installer/manifest.json".text = builtins.toJSON { hosts = hostManifest; };
    "nixos-installer/repo".source = ../../.;
    "profile.d/nixos-installer.sh".text = ''
      alias install-nixos='/run/current-system/sw/bin/nixos-installer'
    '';
  };

  isoImage.storeContents = lib.attrValues hostClosures;
}
