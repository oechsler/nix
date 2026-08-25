# SSH Server Configuration
#
# This module configures OpenSSH server with automatic public key synchronization.
#
# Configuration:
#   features.ssh.enable = false;  # Enable SSH server (default: false)
#
# Features:
# - OpenSSH server with password authentication disabled
# - Automatic import of SSH public keys from a URL or local file
# - Optional acceptance of keys currently loaded in the user's SSH agent
# - Periodic key refresh (every 15 minutes)
#
# How it works:
# 1. Fetches keys from user.keys
# 2. Writes to ~/.ssh/authorized_keys
# 3. Runs on boot (after 30s) and every 15 minutes
#
# Security:
# - Only public key authentication allowed
# - Keys automatically updated if changed on GitHub
# - Proper file permissions (700 for .ssh, 600 for authorized_keys)

{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.features.ssh;
  user = config.users.users.${config.user.name};
  keysFile = "${user.home}/.ssh/authorized_keys";
  agentKeysFile = "${user.home}/.ssh/authorized_keys.agent";

  keySource = toString config.user.keys;
  fetchKeys =
    if lib.hasPrefix "http://" keySource || lib.hasPrefix "https://" keySource then
      "${pkgs.curl}/bin/curl -sf ${lib.escapeShellArg keySource}"
    else
      "${pkgs.coreutils}/bin/cat ${lib.escapeShellArg keySource}";
  syncKeys = pkgs.writeShellScript "sync-authorized-keys" ''
    set -euo pipefail
    keys=$(${fetchKeys} 2>/dev/null)
    if [ -n "$keys" ]; then
      mkdir -p "${user.home}/.ssh"
      temporary=$(mktemp "${keysFile}.XXXXXX")
      trap 'rm -f "$temporary"' EXIT
       {
         printf '# Source: user.keys; last synchronized: %s\n' "$(${pkgs.coreutils}/bin/date -u +%Y-%m-%dT%H:%M:%SZ)"
         printf '%s\n' "$keys"
       } > "$temporary"
      chown ${config.user.name}:${user.group} "${user.home}/.ssh" "$temporary"
      chmod 700 "${user.home}/.ssh"
      chmod 600 "$temporary"
      mv "$temporary" "${keysFile}"
      trap - EXIT
    fi
  '';
  syncAgentKeys = pkgs.writeShellScript "sync-agent-authorized-keys" ''
    set -euo pipefail
    socket="${user.home}/.ssh/proton-pass-agent.sock"
    if [ ! -S "$socket" ]; then
      exit 0
    fi

    keys=$(SSH_AUTH_SOCK="$socket" ${pkgs.openssh}/bin/ssh-add -L 2>/dev/null || true)
    if [ -z "$keys" ] || [ "$keys" = "The agent has no identities." ]; then
      rm -f "${agentKeysFile}"
      exit 0
    fi

    mkdir -p "${user.home}/.ssh"
    temporary=$(mktemp "${agentKeysFile}.XXXXXX")
    trap 'rm -f "$temporary"' EXIT
    {
      printf '# Source: SSH agent; last synchronized: %s\n' "$(${pkgs.coreutils}/bin/date -u +%Y-%m-%dT%H:%M:%SZ)"
      printf '%s\n' "$keys"
    } > "$temporary"
    chown ${config.user.name}:${user.group} "$temporary"
    chmod 600 "$temporary"
    mv "$temporary" "${agentKeysFile}"
    trap - EXIT
  '';
in
{
  options.features.ssh = {
    enable = lib.mkEnableOption "OpenSSH server with public key synchronization";
    agentKeys.enable = (lib.mkEnableOption "SSH-agent keys as authorized keys") // {
      default = true;
    };
  };

  config = lib.mkIf cfg.enable {
    services.openssh = {
      enable = true;
      settings = {
        PasswordAuthentication = false;
        AuthorizedKeysFile =
          ".ssh/authorized_keys" + lib.optionalString cfg.agentKeys.enable " .ssh/authorized_keys.agent";
      };
    };

    systemd = {
      # Synchronize public keys on boot and every 15 minutes
      services.sync-authorized-keys = {
        description = "Synchronize SSH authorized keys";
        after = [ "network-online.target" ];
        wants = [ "network-online.target" ];
        serviceConfig = {
          Type = "oneshot";
          ExecStart = syncKeys;
        };
      };

      timers.sync-authorized-keys = {
        description = "Periodically synchronize SSH keys";
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnBootSec = "30s";
          OnUnitActiveSec = "15min";
        };
      };

      user = {
        services.sync-agent-authorized-keys = lib.mkIf cfg.agentKeys.enable {
          description = "Synchronize SSH agent keys for local SSH access";
          Unit.After = [ "proton-pass-ssh-agent.service" ];
          serviceConfig = {
            Type = "oneshot";
            ExecStart = syncAgentKeys;
            Environment = "SSH_AUTH_SOCK=${user.home}/.ssh/proton-pass-agent.sock";
          };
        };

        timers.sync-agent-authorized-keys = lib.mkIf cfg.agentKeys.enable {
          description = "Periodically synchronize SSH agent keys";
          wantedBy = [ "timers.target" ];
          timerConfig = {
            OnBootSec = "30s";
            OnUnitActiveSec = "15min";
          };
        };
      };
    };
  };
}
