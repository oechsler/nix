# Nix Configuration
#
# This module configures:
# 1. Nix flakes and experimental features
# 2. Unfree package support
# 3. Automatic garbage collection (weekly, 14 days)
# 4. Store optimization (weekly, after GC — never concurrent with builds)
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

{
  config,
  lib,
  pkgs,
  ...
}:

{
  #===========================
  # Configuration
  #===========================

  #---------------------------
  # 1. Nix Features
  #---------------------------
  nix = {
    settings = {
      experimental-features = [
        "nix-command"
        "flakes"
      ];
      # auto-optimise-store is intentionally disabled — it runs inline during
      # builds and can corrupt the store when concurrent builds are happening.
      # Store optimisation is done via a dedicated weekly systemd service instead.
      auto-optimise-store = false;
    };

    #---------------------------
    # 2. Garbage Collection
    #---------------------------
    # Automatically remove old generations to save disk space
    gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 14d"; # Keep last 14 days
    };
  };

  # Store optimisation runs after GC to deduplicate store paths via hardlinks.
  # Runs as a separate weekly service so it never races with active builds.
  systemd.services.nix-store-optimise = {
    description = "Nix store optimisation (deduplication)";
    after = [ "nix-gc.service" ];
    wants = [ "nix-gc.service" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.nix}/bin/nix store optimise";
      Nice = 19;
      IOSchedulingClass = "idle";
    };
  };
  systemd.timers.nix-store-optimise = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "weekly";
      Persistent = true;
      RandomizedDelaySec = "1h";
    };
  };

  # Allow unfree packages (e.g., Discord, Spotify, proprietary drivers)
  nixpkgs.config.allowUnfree = true;

  # nheko depends on libolm which is deprecated but has no maintained replacement yet
  nixpkgs.config.permittedInsecurePackages = [
    "olm-3.2.16"
  ];

  #---------------------------
  # 4. Automatic System Upgrades
  #---------------------------
  system.autoUpgrade = {
    enable = true;
    flake = "${config.users.users.${config.user.name}.home}/repos/nix#${config.networking.hostName}";
    operation = "boot"; # Build but don't activate (requires reboot)
    allowReboot = false; # Never reboot automatically
    flags = [ "--refresh" ]; # Refresh cached evaluations
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
        OnBootSec = "30min"; # First upgrade 30min after boot
        OnUnitActiveSec = "24h"; # Subsequent upgrades every 24h
        Persistent = lib.mkForce false; # Don't run missed upgrades on boot
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
    # - Pull remote (including CI-tested flake.lock) before upgrading
    # - Notify user on success with reboot recommendation
    # - Notify user on failure with error details
    #
    # How it works:
    # - ExecStartPre: Run updateFlake script (git pull — uses CI-tested flake.lock)
    # - ExecStart: Run nixos-rebuild boot (default behavior)
    # - ExecStartPost: Check if reboot is needed and notify
    # - OnFailure: Trigger failure notification service

    services.nixos-upgrade =
      let
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

        # Pre-upgrade script: Sync with remote, then apply Secure Boot override if needed.
        # lanzaboote requires /var/lib/sbctl/keys to exist at build time.
        # If secure-boot-init hasn't run yet, inject a mkForce false override so the
        # build succeeds. The override is cleaned up after the build in ExecStartPost.
        updateFlake = pkgs.writeShellScript "nixos-upgrade-update-flake" ''
          cd ${flakeDir}
          ${pkgs.sudo}/bin/sudo -u ${user} ${pkgs.git}/bin/git checkout flake.lock
          ${pkgs.sudo}/bin/sudo -u ${user} ${pkgs.git}/bin/git pull --ff-only

          # Inject Secure Boot override when keys are missing
          if grep -q 'secureBoot\.enable = true' ${flakeDir}/hosts/$(hostname)/configuration.nix 2>/dev/null \
            && [ ! -f /var/lib/sbctl/keys/db/db.pem ]; then
            OVERRIDE="${flakeDir}/hosts/$(hostname)/secure-boot-upgrade-override.nix"
            printf '{ lib, ... }: { features.secureBoot.enable = lib.mkForce false; }\n' > "$OVERRIDE"
            sed -i '/imports = \[/a\    .\/secure-boot-upgrade-override.nix' \
              ${flakeDir}/hosts/$(hostname)/configuration.nix
            ${pkgs.git}/bin/git -C ${flakeDir} add "$OVERRIDE" \
              ${flakeDir}/hosts/$(hostname)/configuration.nix
          fi
        '';

        # Post-upgrade cleanup: remove Secure Boot override if it was injected
        cleanupOverride = pkgs.writeShellScript "nixos-upgrade-cleanup-override" ''
          OVERRIDE="${flakeDir}/hosts/$(hostname)/secure-boot-upgrade-override.nix"
          if [ -f "$OVERRIDE" ]; then
            sed -i '/secure-boot-upgrade-override\.nix/d' \
              ${flakeDir}/hosts/$(hostname)/configuration.nix
            rm -f "$OVERRIDE"
            ${pkgs.git}/bin/git -C ${flakeDir} rm --cached "$OVERRIDE" 2>/dev/null || true
            ${pkgs.git}/bin/git -C ${flakeDir} add \
              ${flakeDir}/hosts/$(hostname)/configuration.nix
          fi
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
      in
      {
        path = [ pkgs.git pkgs.gnused ];

        serviceConfig.ExecStartPre = lib.mkBefore [ "${updateFlake}" ];
        serviceConfig.ExecStartPost = [ "${cleanupOverride}" "${successScript}" ];

        # Trigger failure notification service on upgrade failure
        unitConfig.OnFailure = [ "nixos-upgrade-notify-failure.service" ];
      };

    #---------------------------
    # 7. Upgrade Failure Notification
    #---------------------------
    # Triggered when nixos-upgrade service fails
    # Shows last 5 error lines from journal in critical notification
    services.nixos-upgrade-notify-failure =
      let
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
      in
      {
        description = "Notify on NixOS upgrade failure";
        serviceConfig = {
          Type = "oneshot";
          ExecStart = "${notify}";
        };
      };
  };
}
