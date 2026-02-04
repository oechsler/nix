{ config, pkgs, lib, ... }:

let
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
      mkdir -p "${user.home}/smb/$LABEL"
      chown ${user.name}:${user.group} "${user.home}/smb/$LABEL"
      for i in $(seq 1 5); do
        mount -t cifs "${path}" "${user.home}/smb/$LABEL" \
          -o credentials=${creds},uid=${toString user.uid},gid=${toString config.users.groups.${user.group}.gid},file_mode=0644,dir_mode=0755 \
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
    after = [ "network-online.target" "sops-nix.service" "systemd-resolved.service" ];
    wants = [ "network-online.target" "systemd-resolved.service" ];
    wantedBy = [ "multi-user.target" ];
    path = [ pkgs.cifs-utils pkgs.util-linux ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${pkgs.bash}/bin/bash ${config.sops.templates."smb-mount.sh".path}";
      ExecStop = "${pkgs.bash}/bin/bash ${config.sops.templates."smb-umount.sh".path}";
      TimeoutStartSec = "60s";
    };
  };
}
