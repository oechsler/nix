{ config, lib, pkgs, ... }:

let
  cfg = config.features.ssh;
  user = config.users.users.${config.user.name};
  keysFile = "${user.home}/.ssh/authorized_keys";

  fetchGithubKeys = pkgs.writeShellScript "fetch-github-keys" ''
    keys=$(${pkgs.curl}/bin/curl -sf "https://github.com/${config.user.github}.keys" 2>/dev/null)
    if [ -n "$keys" ]; then
      mkdir -p "${user.home}/.ssh"
      echo "$keys" > "${keysFile}"
      chown ${config.user.name}:${user.group} "${user.home}/.ssh" "${keysFile}"
      chmod 700 "${user.home}/.ssh"
      chmod 600 "${keysFile}"
    fi
  '';
in
{
  options.features.ssh = {
    enable = lib.mkEnableOption "OpenSSH server with GitHub key import";
  };

  config = lib.mkIf cfg.enable {
    services.openssh = {
      enable = true;
      settings.PasswordAuthentication = false;
    };

    # Fetch GitHub keys on boot and every 15 minutes
    systemd.services.fetch-github-keys = {
      description = "Fetch SSH authorized keys from GitHub";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = fetchGithubKeys;
      };
    };

    systemd.timers.fetch-github-keys = {
      description = "Periodically fetch SSH keys from GitHub";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "30s";
        OnUnitActiveSec = "15min";
      };
    };
  };
}
