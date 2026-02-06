{ config, pkgs, lib, ... }:

let
  cfg = config.features.smb;

  smbShares = [ "personal-drive" ];
  user = config.users.users.samuel;

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
      for i in $(seq 1 5); do
        mount -t cifs "${path}" "${user.home}/smb/$LABEL" \
          -o credentials=${creds},uid=$MOUNT_UID,gid=$MOUNT_GID,forceuid,forcegid,file_mode=0644,dir_mode=0755 \
          && break
        echo "Mount-Versuch $i/5 fehlgeschlagen: $LABEL"
        sleep 5
      done
    ''
  ) smbShares;

  umountContent = lib.concatMapStringsSep "\n" (name:
    let label = config.sops.placeholder."smb/${name}/label";
    in ''
      umount "${user.home}/smb/${label}" || true
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
      after = [ "network-online.target" "sops-nix.service" "systemd-resolved.service" ]
        ++ lib.optionals config.features.tailscale.enable [ "tailscaled.service" ];
      wants = [ "network-online.target" "systemd-resolved.service" ]
        ++ lib.optionals config.features.tailscale.enable [ "tailscaled.service" ];
      # No wantedBy — triggered by timer so it never blocks boot
      path = [ pkgs.cifs-utils pkgs.util-linux ]
        ++ lib.optionals config.features.tailscale.enable [ config.services.tailscale.package ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "${pkgs.bash}/bin/bash ${config.sops.templates."smb-mount.sh".path}";
        ExecStop = "${pkgs.bash}/bin/bash ${config.sops.templates."smb-umount.sh".path}";
        Restart = "on-failure";
        RestartSec = "30s";
      };
    };

    systemd.timers.smb-mount = {
      description = "Mount SMB shares after boot";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "15s";
      };
    };
  };
}
