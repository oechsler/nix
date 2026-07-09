# SMB Network Share Configuration
#
# This module configures:
# 1. Automatic SMB/CIFS network share mounting at boot
# 2. Network and DNS readiness waiting before mount attempts
# 3. Mount retries with timeout and desktop notifications
# 4. Graceful unmounting on shutdown
#
# Configuration options:
#   features.smb.enable = true;
#   features.smb.shares = [
#     { name = "personal-drive"; label = "Personal-drive"; path = "//server/share"; }
#   ];
#
# username is derived automatically from config.user.name.
#
# Required SOPS secret for each share:
#   smb/<name>/password - SMB password
#
# Shares are mounted to:
#   ~/smb/<label>/  (e.g., ~/smb/Personal-drive/)

{
  config,
  pkgs,
  lib,
  ...
}:

let
  cfg = config.features.smb;
  user = config.users.users.${config.user.name};

  # ============================================================================
  # NETWORK READINESS CHECK
  # ============================================================================
  waitForNetwork = pkgs.writeShellScript "wait-for-network" ''
    echo "Waiting for network and DNS..."
    for i in $(seq 1 30); do
      if ${pkgs.iproute2}/bin/ip route | ${pkgs.gnugrep}/bin/grep -q '^default'; then
        if ${pkgs.systemd}/bin/resolvectl query google.com >/dev/null 2>&1; then
          echo "Network and DNS ready"
          exit 0
        fi
      fi
      echo "Waiting for network... Attempt $i/30"
      sleep 2
    done
    echo "Warning: Network not ready after 60 seconds, continuing anyway..."
    exit 0
  '';

  # ============================================================================
  # MOUNT SCRIPT
  # ============================================================================
  mountContent = lib.concatMapStringsSep "\n" (
    share:
    let
      creds = config.sops.templates."smb-credentials-${share.name}".path;
    in
    ''
      LABEL="${share.label}"
      MOUNT_UID=$(id -u ${user.name})
      MOUNT_GID=$(id -g ${user.name})

      mkdir -p "${user.home}/smb/$LABEL"
      chown ${user.name}:${user.group} "${user.home}/smb/$LABEL"

      if mountpoint -q "${user.home}/smb/$LABEL"; then
        echo "SMB already mounted: $LABEL"
      else
        MOUNTED=false
        for i in $(seq 1 5); do
          if timeout 10 mount -t cifs "${share.path}" "${user.home}/smb/$LABEL" \
            -o credentials=${creds},uid=$MOUNT_UID,gid=$MOUNT_GID,forceuid,forcegid,soft,file_mode=0644,dir_mode=0755; then
            MOUNTED=true
            break
          fi
          echo "Mount attempt $i/5 failed: $LABEL"
          sleep 5
        done

        if [ "$MOUNTED" = true ]; then
          echo "SMB mount successful: $LABEL"
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
  umountContent = lib.concatMapStringsSep "\n" (
    share: ''
      umount -l "${user.home}/smb/${share.label}" || true
    ''
  ) cfg.shares;
in
{
  #===========================
  # Options
  #===========================

  options.features.smb = {
    enable = (lib.mkEnableOption "SMB network share mounts") // {
      default = true;
    };
    shares = lib.mkOption {
      type = lib.types.listOf (
        lib.types.submodule {
          options = {
            name = lib.mkOption {
              type = lib.types.str;
              description = "Internal share identifier — used as sops key (smb/<name>/password) and credential file name.";
            };
            label = lib.mkOption {
              type = lib.types.str;
              description = "Display name and mount directory under ~/smb/.";
            };
            path = lib.mkOption {
              type = lib.types.str;
              description = "SMB share path, e.g. //server/share.";
            };
            username = lib.mkOption {
              type = lib.types.str;
              default = config.user.name;
              description = "SMB username. Defaults to config.user.name.";
            };
          };
        }
      );
      default = [ ];
      description = "SMB shares to mount. username defaults to config.user.name. Only the password needs a sops secret (smb/<name>/password).";
    };
  };

  #===========================
  # Configuration
  #===========================

  config = lib.mkIf (cfg.enable && cfg.shares != [ ]) {

    environment.systemPackages = [ pkgs.cifs-utils ];

    systemd = {
      tmpfiles.rules = [
        "d ${user.home}/smb 0755 ${user.name} ${user.group} -"
      ];

      services.smb-mount = {
        description = "Mount SMB Shares";

        after = [
          "network-online.target"
          "systemd-resolved.service"
          "graphical.target"
          "sops-install-secrets.service"
        ];
        wants = [
          "network-online.target"
          "systemd-resolved.service"
        ];
        wantedBy = [ "graphical.target" ];

        unitConfig.ConditionPathExists = config.sops.age.keyFile;

        path = [
          pkgs.cifs-utils
          pkgs.util-linux
          pkgs.sudo
          pkgs.libnotify
          pkgs.iproute2
          pkgs.systemd
        ];

        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStartPre = "${waitForNetwork}";
          ExecStart = "${pkgs.bash}/bin/bash ${config.sops.templates."smb-mount.sh".path}";
          ExecStop = "${pkgs.bash}/bin/bash ${config.sops.templates."smb-umount.sh".path}";
        };
      };
    };

    sops = {
      templates =
        lib.listToAttrs (
          map (share: {
            name = "smb-credentials-${share.name}";
            value.content = ''
              username=${share.username}
              password=${config.sops.placeholder."smb/${share.name}/password"}
            '';
          }) cfg.shares
        )
        // {
          "smb-mount.sh".content = "#!/bin/bash\n" + mountContent;
          "smb-umount.sh".content = "#!/bin/bash\n" + umountContent;
        };

      secrets = lib.listToAttrs (
        map (share: {
          name = "smb/${share.name}/password";
          value = { };
        }) cfg.shares
      );
    };

  };
}
