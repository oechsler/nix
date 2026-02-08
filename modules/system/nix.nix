{ config, pkgs, ... }:

{
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  nixpkgs.config.allowUnfree = true;

  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 14d";
  };

  nix.settings.auto-optimise-store = true;

  system.autoUpgrade = {
    enable = true;
    flake = "${config.users.users.${config.user.name}.home}/repos/nix#${config.networking.hostName}";
    dates = "daily";
    allowReboot = false;
  };

  systemd.services.nixos-upgrade = let
    uid = toString config.users.users.${config.user.name}.uid;
    notify = pkgs.writeShellScript "nixos-upgrade-notify" ''
      ${pkgs.sudo}/bin/sudo -u ${config.user.name} \
        DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/${uid}/bus" \
        ${pkgs.libnotify}/bin/notify-send "$1" "$2"
    '';
  in {
    serviceConfig.ExecStartPost =
      "${notify} 'NixOS Upgrade' 'System erfolgreich aktualisiert'";
    unitConfig.OnFailure = [ "nixos-upgrade-notify-failure.service" ];
  };

  systemd.services.nixos-upgrade-notify-failure = {
    description = "Notify on NixOS upgrade failure";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = let uid = toString config.users.users.${config.user.name}.uid; in
        "${pkgs.writeShellScript "nixos-upgrade-notify-failure" ''
          ${pkgs.sudo}/bin/sudo -u ${config.user.name} \
            DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/${uid}/bus" \
            ${pkgs.libnotify}/bin/notify-send -u critical \
              "NixOS Upgrade" "Upgrade fehlgeschlagen!"
        ''}";
    };
  };
}
