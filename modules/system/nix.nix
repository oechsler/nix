{ config, lib, pkgs, ... }:

{
  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];
  };
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
    operation = "boot";
    allowReboot = false;
    flags = [ "--refresh" ];
  };

  systemd.timers.nixos-upgrade = {
    timerConfig = {
      OnBootSec = "30min";
      OnUnitActiveSec = "24h";
      Persistent = lib.mkForce false;
    };
  };

  environment.etc.gitconfig.text = ''
    [safe]
      directory = ${config.users.users.${config.user.name}.home}/repos/nix
  '';

  systemd.services.nixos-upgrade = let
    flakeDir = "${config.users.users.${config.user.name}.home}/repos/nix";

    notify = pkgs.writeShellScript "nixos-upgrade-notify" ''
      ${pkgs.systemd}/bin/systemd-run --machine=${config.user.name}@ \
        --user --pipe --quiet --collect \
        ${pkgs.libnotify}/bin/notify-send "$@"
    '';

    updateFlake = pkgs.writeShellScript "nixos-upgrade-update-flake" ''
      cd ${flakeDir}
      ${pkgs.sudo}/bin/sudo -u ${config.user.name} ${pkgs.nix}/bin/nix flake update
    '';

    successScript = pkgs.writeShellScript "nixos-upgrade-success" ''
      current=$(readlink /run/current-system)
      booted=$(readlink /run/booted-system)
      if [ "$current" != "$booted" ]; then
        ${notify} -u normal \
          "Systemaktualisierung abgeschlossen" \
          "Ein Neustart wird empfohlen."
      else
        ${notify} -u low \
          "Systemaktualisierung" \
          "Das System ist bereits auf dem neuesten Stand."
      fi
    '';
  in {
    path = [ pkgs.git ];
    serviceConfig.ExecStartPre = "${updateFlake}";
    serviceConfig.ExecStartPost = "${successScript}";
    unitConfig.OnFailure = [ "nixos-upgrade-notify-failure.service" ];
  };

  systemd.services.nixos-upgrade-notify-failure = let
    notify = pkgs.writeShellScript "nixos-upgrade-notify-failure" ''
      error=$(${pkgs.systemd}/bin/journalctl -u nixos-upgrade.service -b --no-pager -p err -o cat | tail -5)
      ${pkgs.systemd}/bin/systemd-run --machine=${config.user.name}@ \
        --user --pipe --quiet --collect \
        ${pkgs.libnotify}/bin/notify-send -u critical \
          "Systemaktualisierung fehlgeschlagen" \
          "Die automatische Aktualisierung konnte nicht durchgeführt werden.\n\n$error"
    '';
  in {
    description = "Notify on NixOS upgrade failure";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${notify}";
    };
  };
}
