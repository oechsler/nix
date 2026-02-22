# SMB Network Share Configuration
#
# This module configures:
# 1. Automatic SMB/CIFS network share mounting at boot
# 2. Network and DNS readiness waiting before mount attempts
# 3. Mount retries with timeout and desktop notifications
# 4. Graceful unmounting on shutdown
#
# Configuration options:
#   features.smb.enable = true;                      # Enable SMB mounts (default: true)
#   features.smb.shares = [ "personal-drive" ];      # SMB shares to mount (default: ["personal-drive"])
#
# Required SOPS secrets for each share:
#   smb/<name>/label    - Display name (e.g., "Personal Drive")
#   smb/<name>/path     - SMB path (e.g., "//server/share")
#   smb/<name>/username - SMB username
#   smb/<name>/password - SMB password
#
# Shares are mounted to:
#   ~/smb/<label>/  (e.g., ~/smb/Personal Drive/)
#
# How it works:
# - Waits for network and DNS (up to 60 seconds)
# - Mounts shares with retry logic (5 attempts, 10s timeout each)
# - Shows desktop notifications on success/failure
# - Unmounts gracefully on shutdown

{ config, pkgs, lib, ... }:

let
  cfg = config.features.smb;
  user = config.users.users.${config.user.name};

  # ============================================================================
  # NETWORK READINESS CHECK
  # ============================================================================
  # Why: SMB mounts fail if attempted before network and DNS are ready.
  #
  # Problem: systemd's network-online.target doesn't guarantee DNS is working.
  #
  # Solution: Explicitly wait for both default route and DNS resolution.
  #
  # How it works:
  # - Check for default route (ip route | grep '^default')
  # - Check DNS by resolving google.com (resolvectl query)
  # - Retry every 2 seconds for up to 60 seconds
  # - Continue anyway after timeout (allows manual mount later)
  waitForNetwork = pkgs.writeShellScript "wait-for-network" ''
    echo "Waiting for network and DNS..."
    for i in $(seq 1 30); do
      # Check if we have a default route (internet connectivity)
      if ${pkgs.iproute2}/bin/ip route | ${pkgs.gnugrep}/bin/grep -q '^default'; then
        # Check if DNS is working by resolving a known domain
        if ${pkgs.systemd}/bin/resolvectl query google.com >/dev/null 2>&1; then
          echo "Network and DNS ready"
          exit 0
        fi
      fi
      echo "Waiting for network... Attempt $i/30"
      sleep 2
    done
    echo "Warning: Network not ready after 60 seconds, continuing anyway..."
    exit 0  # Don't fail the service, just continue
  '';

  # ============================================================================
  # SOPS SECRETS CONFIGURATION
  # ============================================================================
  # Generate SOPS secret definitions for all SMB shares
  # For each share in cfg.shares, we need 4 secrets:
  # - label: Display name (e.g., "Personal Drive")
  # - path: SMB path (e.g., "//192.168.1.100/share")
  # - username: SMB username
  # - password: SMB password
  smbSecrets = lib.listToAttrs (lib.flatten (map (name: [
    { name = "smb/${name}/label"; value = {}; }
    { name = "smb/${name}/path"; value = {}; }
    { name = "smb/${name}/username"; value = {}; }
    { name = "smb/${name}/password"; value = {}; }
  ]) cfg.shares));

  # ============================================================================
  # MOUNT SCRIPT
  # ============================================================================
  # Generate mount script for all SMB shares
  #
  # For each share:
  # 1. Create mount directory (~/smb/<label>/)
  # 2. Check if already mounted (skip if yes)
  # 3. Try mounting up to 5 times with 10s timeout each
  # 4. Show desktop notification on success/failure
  #
  # Mount options:
  # - credentials=${creds} - Read username/password from SOPS template
  # - uid/gid - Mount as user (not root)
  # - forceuid/forcegid - Override server-provided ownership
  # - soft - Allow mount to be interrupted if server is down
  # - file_mode/dir_mode - Set permissions (644 for files, 755 for dirs)
  mountContent = lib.concatMapStringsSep "\n" (name:
    let
      creds = config.sops.templates."smb-credentials-${name}".path;
      label = config.sops.placeholder."smb/${name}/label";
      path = config.sops.placeholder."smb/${name}/path";
    in ''
      LABEL="${label}"
      MOUNT_UID=$(id -u ${user.name})
      MOUNT_GID=$(id -g ${user.name})

      # Create mount directory and set ownership
      mkdir -p "${user.home}/smb/$LABEL"
      chown ${user.name}:${user.group} "${user.home}/smb/$LABEL"

      # Check if already mounted (e.g., manual mount or service restart)
      if mountpoint -q "${user.home}/smb/$LABEL"; then
        echo "SMB already mounted: $LABEL"
      else
        # Try mounting with retries
        # Why retries: Server might not be ready yet, network might be slow
        MOUNTED=false
        for i in $(seq 1 5); do
          # Timeout after 10 seconds to prevent hanging
          if timeout 10 mount -t cifs "${path}" "${user.home}/smb/$LABEL" \
            -o credentials=${creds},uid=$MOUNT_UID,gid=$MOUNT_GID,forceuid,forcegid,soft,file_mode=0644,dir_mode=0755; then
            MOUNTED=true
            break
          fi
          echo "Mount attempt $i/5 failed: $LABEL"
          sleep 5  # Wait before retry
        done

        # Show notification with result
        if [ "$MOUNTED" = true ]; then
          echo "SMB mount successful: $LABEL"
          # Send desktop notification as user (not root)
          # DBUS_SESSION_BUS_ADDRESS is needed for notify-send to work from system service
          sudo -u ${user.name} DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$MOUNT_UID/bus \
            ${pkgs.libnotify}/bin/notify-send -a "SMB Mount" -i network-server "SMB-Mount erfolgreich" "$LABEL wurde verbunden"
        else
          echo "Mount failed after 5 attempts: $LABEL"
          sudo -u ${user.name} DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$MOUNT_UID/bus \
            ${pkgs.libnotify}/bin/notify-send -a "SMB Mount" -u critical -i dialog-error "SMB-Mount fehlgeschlagen" "$LABEL konnte nicht verbunden werden"
          exit 1
        fi
      fi
    ''
  ) cfg.shares;

  # ============================================================================
  # UNMOUNT SCRIPT
  # ============================================================================
  # Generate unmount script for all SMB shares
  #
  # Uses lazy unmount (-l) to detach even if share is busy
  # || true ensures the service doesn't fail if unmount fails
  umountContent = lib.concatMapStringsSep "\n" (name:
    let label = config.sops.placeholder."smb/${name}/label";
    in ''
      # Lazy unmount: detach immediately, clean up when no longer busy
      umount -l "${user.home}/smb/${label}" || true
    ''
  ) cfg.shares;
in
{
  #===========================
  # Options
  #===========================

  options.features.smb = {
    enable = (lib.mkEnableOption "SMB network share mounts") // { default = true; };
    shares = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "personal-drive" ];
      description = "SMB share names to mount — each needs smb/<name>/{label,path,username,password} SOPS secrets";
    };
  };

  #===========================
  # Configuration
  #===========================

  config = lib.mkIf cfg.enable {

    #---------------------------
    # 1. SMB Support Package
    #---------------------------
    environment.systemPackages = [ pkgs.cifs-utils ];

    #---------------------------
    # 2. Mount Directory
    #---------------------------
    # Create ~/smb/ directory with correct ownership
    systemd.tmpfiles.rules = [
      "d ${user.home}/smb 0755 ${user.name} ${user.group} -"
    ];

    #---------------------------
    # 3. SOPS Secrets and Templates
    #---------------------------
    sops = {
      # Generate credential files for each share
      # Format: username=<user>\npassword=<pass>
      # Used by mount.cifs via -o credentials=<file>
      templates = lib.listToAttrs (map (name: {
        name = "smb-credentials-${name}";
        value.content = ''
          username=${config.sops.placeholder."smb/${name}/username"}
          password=${config.sops.placeholder."smb/${name}/password"}
        '';
      }) cfg.shares) // {
        # Mount script (generated from mountContent)
        "smb-mount.sh".content = "#!/bin/bash\n" + mountContent;
        # Unmount script (generated from umountContent)
        "smb-umount.sh".content = "#!/bin/bash\n" + umountContent;
      };

      # Declare all required secrets
      secrets = smbSecrets;
    };

    #---------------------------
    # 4. SMB Mount Service
    #---------------------------
    # Runs at boot after network is ready
    # Mounts all configured SMB shares
    systemd.services.smb-mount = {
      description = "Mount SMB Shares";

      # Wait for network, DNS, GUI session, and SOPS secrets
      after = [ "network-online.target" "systemd-resolved.service" "graphical.target" "sops-install-secrets.service" ]
        ++ lib.optionals config.features.tailscale.enable [ "tailscaled.service" ];
      wants = [ "network-online.target" "systemd-resolved.service" ]
        ++ lib.optionals config.features.tailscale.enable [ "tailscaled.service" ];

      # Start when GUI is ready (so notifications work)
      wantedBy = [ "graphical.target" ];

      # Skip gracefully if SOPS key doesn't exist (fresh install without secrets)
      unitConfig.ConditionPathExists = config.sops.age.keyFile;

      # Required tools for mount script
      path = [ pkgs.cifs-utils pkgs.util-linux pkgs.sudo pkgs.libnotify pkgs.iproute2 pkgs.systemd ]
        ++ lib.optionals config.features.tailscale.enable [ config.services.tailscale.package ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;  # Consider service active after mount completes

        # Pre-start: Wait for network and DNS
        ExecStartPre = "${waitForNetwork}";

        # Start: Mount all shares
        ExecStart = "${pkgs.bash}/bin/bash ${config.sops.templates."smb-mount.sh".path}";

        # Stop: Unmount all shares (on shutdown)
        ExecStop = "${pkgs.bash}/bin/bash ${config.sops.templates."smb-umount.sh".path}";
      };
    };
  };
}
