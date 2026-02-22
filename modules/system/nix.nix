# Nix Configuration
#
# This module configures:
# 1. Nix flakes and experimental features
# 2. Unfree package support
# 3. Automatic garbage collection (weekly, 14 days)
# 4. Store optimization (deduplication)
# 5. Automatic system upgrades with notifications
#
# Automatic upgrades:
# - Runs daily (24h after last upgrade, or 30min after boot)
# - Updates flake.lock before upgrading
# - Rebuilds system but doesn't activate (requires reboot)
# - Shows desktop notifications on success/failure
# - Recommends reboot when system changed
#
# How it works:
# 1. Pull latest changes from git (repos/nix)
# 2. Update flake.lock (nix flake update)
# 3. Build new system generation (nixos-rebuild boot)
# 4. Compare current vs booted system
# 5. Notify user if reboot is needed
#
# Notifications:
# - Success: "Systemaktualisierung abgeschlossen" (if reboot needed)
# - No change: "Das System ist bereits auf dem neuesten Stand"
# - Failure: Shows last 5 error lines from journal

{ config, lib, pkgs, ... }:

{
  #===========================
  # Configuration
  #===========================

  #---------------------------
  # 1. Nix Features
  #---------------------------
  nix = {
    settings = {
      experimental-features = [ "nix-command" "flakes" ];
      # Deduplicate identical files in /nix/store
      # Saves disk space by hardlinking duplicate files
      auto-optimise-store = true;
    };

    #---------------------------
    # 2. Garbage Collection
    #---------------------------
    # Automatically remove old generations to save disk space
    gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 14d";  # Keep last 14 days
    };
  };

  # Allow unfree packages (e.g., Discord, Spotify, proprietary drivers)
  nixpkgs.config.allowUnfree = true;

  #---------------------------
  # 4. Automatic System Upgrades
  #---------------------------
  system.autoUpgrade = {
    enable = true;
    flake = "${config.users.users.${config.user.name}.home}/repos/nix#${config.networking.hostName}";
    operation = "boot";  # Build but don't activate (requires reboot)
    allowReboot = false;  # Never reboot automatically
    flags = [ "--refresh" ];  # Refresh cached evaluations
  };

  #---------------------------
  # 5. Git Configuration
  #---------------------------
  # Mark flake directory as safe for git operations
  # Needed because nixos-upgrade runs as root but operates on user-owned repo
  environment.etc.gitconfig.text = ''
    [safe]
      directory = ${config.users.users.${config.user.name}.home}/repos/nix
  '';

  systemd = {
    # Upgrade schedule
    timers.nixos-upgrade = {
      timerConfig = {
        OnBootSec = "30min";  # First upgrade 30min after boot
        OnUnitActiveSec = "24h";  # Subsequent upgrades every 24h
        Persistent = lib.mkForce false;  # Don't run missed upgrades on boot
      };
    };

  #---------------------------
  # 6. Upgrade Customization
  #---------------------------
  # Why: The default nixos-upgrade service doesn't update flake.lock or notify the user.
  #
  # Problem: Users don't know when upgrades succeed/fail or when reboot is needed.
  #
  # Solution: Customize nixos-upgrade service to:
  # - Update flake.lock before upgrading (get latest packages)
  # - Notify user on success with reboot recommendation
  # - Notify user on failure with error details
  #
  # How it works:
  # - ExecStartPre: Run updateFlake script (git pull + nix flake update)
  # - ExecStart: Run nixos-rebuild boot (default behavior)
  # - ExecStartPost: Check if reboot is needed and notify
  # - OnFailure: Trigger failure notification service

    services.nixos-upgrade = let
    flakeDir = "${config.users.users.${config.user.name}.home}/repos/nix";
    user = config.user.name;

    # Helper script to send desktop notifications from system service
    # Why: System services don't have access to user D-Bus session
    # Solution: Use systemd-run --machine=<user>@ to run notify-send in user session
    notify = pkgs.writeShellScript "nixos-upgrade-notify" ''
      ${pkgs.systemd}/bin/systemd-run --machine=${user}@ \
        --user --pipe --quiet --collect \
        ${pkgs.libnotify}/bin/notify-send "$@"
    '';

    # Pre-upgrade script: Update flake.lock
    # Steps:
    # 1. Reset flake.lock to git HEAD (discard local changes)
    # 2. Pull latest changes from remote (git pull --ff-only)
    # 3. Update flake.lock (nix flake update)
    #
    # Note: All operations run as user (sudo -u) not root, to preserve git ownership
    updateFlake = pkgs.writeShellScript "nixos-upgrade-update-flake" ''
      cd ${flakeDir}
      ${pkgs.sudo}/bin/sudo -u ${user} ${pkgs.git}/bin/git checkout flake.lock
      ${pkgs.sudo}/bin/sudo -u ${user} ${pkgs.git}/bin/git pull --ff-only
      ${pkgs.sudo}/bin/sudo -u ${user} ${pkgs.nix}/bin/nix flake update
    '';

    # Post-upgrade success script
    # Compare /run/current-system (newly built) vs /run/booted-system (currently running)
    # If different: Reboot recommended
    # If same: System already up-to-date
    successScript = pkgs.writeShellScript "nixos-upgrade-success" ''
      current=$(readlink /run/current-system)
      booted=$(readlink /run/booted-system)
      if [ "$current" != "$booted" ]; then
        # New system generation built, reboot needed to activate
        ${notify} -u normal \
          "Systemaktualisierung abgeschlossen" \
          "Ein Neustart wird empfohlen."
      else
        # No changes, system already up-to-date
        ${notify} -u low \
          "Systemaktualisierung" \
          "Das System ist bereits auf dem neuesten Stand."
      fi
    '';
  in {
    path = [ pkgs.git ];

    serviceConfig.ExecStartPre = lib.mkBefore [ "${updateFlake}" ];
    serviceConfig.ExecStartPost = "${successScript}";

    # Trigger failure notification service on upgrade failure
    unitConfig.OnFailure = [ "nixos-upgrade-notify-failure.service" ];
  };

    #---------------------------
    # 7. Upgrade Failure Notification
    #---------------------------
    # Triggered when nixos-upgrade service fails
    # Shows last 5 error lines from journal in critical notification
    services.nixos-upgrade-notify-failure = let
    notify = pkgs.writeShellScript "nixos-upgrade-notify-failure" ''
      # Extract last 5 error lines from nixos-upgrade journal
      error=$(${pkgs.systemd}/bin/journalctl -u nixos-upgrade.service -b --no-pager -p err -o cat | tail -5)

      # Send critical notification to user session
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
  };
}
