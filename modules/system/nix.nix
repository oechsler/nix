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

  environment.etc.gitconfig.text = ''
    [safe]
      directory = ${config.users.users.${config.user.name}.home}/repos/nix
  '';

  systemd.services.nixos-upgrade = let
    notify = pkgs.writeShellScript "nixos-upgrade-notify" ''
      ${pkgs.systemd}/bin/systemd-run --machine=${config.user.name}@ \
        --user --pipe --quiet --collect \
        ${pkgs.libnotify}/bin/notify-send "$@"
    '';
  in {
    path = [ pkgs.git ];
    serviceConfig.ExecStartPost =
      "${notify} 'NixOS Upgrade' 'System erfolgreich aktualisiert'";
    unitConfig.OnFailure = [ "nixos-upgrade-notify-failure.service" ];
  };

  systemd.services.nixos-upgrade-notify-failure = {
    description = "Notify on NixOS upgrade failure";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.writeShellScript "nixos-upgrade-notify-failure" ''
        ${pkgs.systemd}/bin/systemd-run --machine=${config.user.name}@ \
          --user --pipe --quiet --collect \
          ${pkgs.libnotify}/bin/notify-send -u critical \
            "NixOS Upgrade" "Aktualisierung fehlgeschlagen"
      ''}";
    };
  };
}
