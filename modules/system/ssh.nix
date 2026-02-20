# SSH Server Configuration
#
# This module configures OpenSSH server with automatic GitHub key import.
#
# Configuration:
#   features.ssh.enable = false;  # Enable SSH server (default: false)
#
# Features:
# - OpenSSH server with password authentication disabled
# - Automatic import of SSH public keys from GitHub
# - Periodic key refresh (every 15 minutes)
#
# How it works:
# 1. Fetches keys from https://github.com/{user.github}.keys
# 2. Writes to ~/.ssh/authorized_keys
# 3. Runs on boot (after 30s) and every 15 minutes
#
# Security:
# - Only public key authentication allowed
# - Keys automatically updated if changed on GitHub
# - Proper file permissions (700 for .ssh, 600 for authorized_keys)

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
