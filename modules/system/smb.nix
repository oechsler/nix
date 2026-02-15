{ config, pkgs, lib, ... }:

let
  cfg = config.features.smb;

  smbShares = [ "personal-drive" ];
  user = config.users.users.samuel;

  # Wait for network and DNS to be ready
  waitForNetwork = pkgs.writeShellScript "wait-for-network" ''
    echo "Waiting for network and DNS..."
    for i in $(seq 1 30); do
      # Check if we have a default route
      if ${pkgs.iproute2}/bin/ip route | ${pkgs.gnugrep}/bin/grep -q '^default'; then
        # Check if DNS is working
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

  smbSecrets = lib.listToAttrs (lib.flatten (map (name: [
    { name = "smb/${name}/label"; value = {}; }
    { name = "smb/${name}/path"; value = {}; }
    { name = "smb/${name}/username"; value = {}; }
    { name = "smb/${name}/password"; value = {}; }
  ]) smbShares));

  mountContent = lib.concatMapStringsSep "\n" (name:
    let
      creds = config.sops.templates."smb-credentials-${name}".path;
      label = config.sops.placeholder."smb/${name}/label";
      path = config.sops.placeholder."smb/${name}/path";
    in ''
      LABEL="${label}"
      MOUNT_UID=$(id -u ${user.name})
      MOUNT_GID=$(id -g ${user.name})
      mkdir -p "${user.home}/smb/$LABEL"
      chown ${user.name}:${user.group} "${user.home}/smb/$LABEL"
      if mountpoint -q "${user.home}/smb/$LABEL"; then
        echo "SMB already mounted: $LABEL"
      else
        MOUNTED=false
        for i in $(seq 1 5); do
          if timeout 10 mount -t cifs "${path}" "${user.home}/smb/$LABEL" \
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
  ) smbShares;

  umountContent = lib.concatMapStringsSep "\n" (name:
    let label = config.sops.placeholder."smb/${name}/label";
    in ''
      umount -l "${user.home}/smb/${label}" || true
    ''
  ) smbShares;
in
{
  options.features.smb = {
    enable = (lib.mkEnableOption "SMB network share mounts") // { default = true; };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ pkgs.cifs-utils ];

    systemd.tmpfiles.rules = [
      "d ${user.home}/smb 0755 ${user.name} ${user.group} -"
    ];

    sops = {
      templates = lib.listToAttrs (map (name: {
        name = "smb-credentials-${name}";
        value.content = ''
          username=${config.sops.placeholder."smb/${name}/username"}
          password=${config.sops.placeholder."smb/${name}/password"}
        '';
      }) smbShares) // {
        "smb-mount.sh".content = "#!/bin/bash\n" + mountContent;
        "smb-umount.sh".content = "#!/bin/bash\n" + umountContent;
      };
      secrets = smbSecrets;
    };

    systemd.services.smb-mount = {
      description = "Mount SMB Shares";
      after = [ "network-online.target" "systemd-resolved.service" "graphical.target" "sops-install-secrets.service" ]
        ++ lib.optionals config.features.tailscale.enable [ "tailscaled.service" ];
      wants = [ "network-online.target" "systemd-resolved.service" ]
        ++ lib.optionals config.features.tailscale.enable [ "tailscaled.service" ];
      wantedBy = [ "graphical.target" ];

      # Skip gracefully if SOPS key doesn't exist (fresh install)
      unitConfig.ConditionPathExists = config.sops.age.keyFile;

      path = [ pkgs.cifs-utils pkgs.util-linux pkgs.sudo pkgs.libnotify pkgs.iproute2 pkgs.systemd ]
        ++ lib.optionals config.features.tailscale.enable [ config.services.tailscale.package ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStartPre = "${waitForNetwork}";
        ExecStart = "${pkgs.bash}/bin/bash ${config.sops.templates."smb-mount.sh".path}";
        ExecStop = "${pkgs.bash}/bin/bash ${config.sops.templates."smb-umount.sh".path}";
      };
    };
  };
}
